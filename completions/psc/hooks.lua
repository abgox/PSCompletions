local function without_reset(items)
    return psc.filter(items, function(it)
        return not psc.eq(it.name, "--reset")
    end)
end

---@diagnostic disable-next-line: undefined-field
local d = psc._data or {}
local cs = {}
local unknown = {}
for _, t in ipairs(psc.tokens) do
    if t.type == "unknown" then
        table.insert(unknown, t.input)
    end
end
local cmd1, cmd2 = psc.cmds[1], psc.cmds[2]

if not cmd1 then
    if #(d.remote or {}) > 0 then
        psc.set_symbol("add", "switch")
    end
    if #(d.list or {}) > 0 then
        psc.set_symbol("rm", "switch")
        psc.set_symbol("info", "switch")
    end
elseif psc.eq(cmd1, "alias") then
    if not cmd2 and #(d.list or {}) > 0 then
        psc.set_symbol("add", "switch")
        psc.set_symbol("rm", "switch")
    end
end

-- Commands that never take --reset (add/rm/update/info/list): drop the bubbled-up root --reset
local no_reset = psc.contains({ "add", "rm", "update", "info", "list" }, cmd1)
local static_items = no_reset and without_reset(completions) or completions

-- completion/config build or hide options dynamically, so option completion can't early-return; others reuse static
if psc.current.option_like and not psc.contains({ "completion", "config" }, cmd1) then
    return static_items
end

-- Completion-name tip: pull url/description from completions.json meta (localized)
local function completion_tip(name)
    local meta = d.meta and d.meta[name]
    if not meta then
        return nil
    end
    local lang = d.config and d.config.language
    local c = meta[lang] or meta["en-US"]
    if not c then
        return nil
    end
    local lines = {}
    if c.url then
        table.insert(lines, "url: " .. c.url)
    end
    if c.description then
        table.insert(lines, "-----")
        table.insert(lines, psc.join(c.description, "\n"))
    end
    return psc.join(lines, "\n")
end

-- Render info tips: substitute {{ $completion }} / {{ $language }} / {{ $value }}; special-case the "Current trigger aliases" line
local function render_tip(lines, vars)
    if type(lines) == "string" then
        lines = { lines }
    end
    local out = {}
    for _, line in ipairs(lines or {}) do
        local s = line
        -- The {{ "prefix $($PSCompletions.data.alias.$completion -join ' ')" }} line: extract prefix + join aliases
        local expr_prefix = s:match('^{{%s*"(.-)%$%(%$PSCompletions%.data%.alias%.%$completion')
        if expr_prefix then
            s = expr_prefix .. psc.join((d.alias and d.alias[vars.completion]) or {}, " ")
        else
            for k, v in pairs(vars) do
                s = s:gsub("{{ %$" .. k .. " }}", tostring(v))
            end
        end
        table.insert(out, s)
    end
    return psc.join(out, "\n")
end

-- Target completion language: user override > module language > first supported language
local function target_language(name, cfg)
    if not cfg or not cfg.language or #cfg.language == 0 then
        return "en-US"
    end
    local pcc = (d.config and d.config.completion and d.config.completion[name]) or {}
    local override = pcc.language
    if override then
        if psc.contains(cfg.language, override) then
            return override
        end
        return cfg.language[1]
    end
    local modlang = d.config and d.config.language
    if modlang and psc.contains(cfg.language, modlang) then
        return modlang
    end
    return cfg.language[1]
end

-- Settings-registered completions + real dirs on disk (orphans/dead links visible in rm/info/update)
local function add_completions(include_dirs, symbol)
    local rest = {}
    local seen = {}
    for _, name in ipairs(d.list or {}) do
        if not psc.typed_unknown(name) then
            table.insert(rest, name)
            seen[name] = true
        end
    end
    if include_dirs and d.completions then
        for _, e in ipairs(psc.ls(d.completions) or {}) do
            local name = e.name
            if (e.is_dir or e.is_link) and not seen[name] and not psc.typed_unknown(name) then
                table.insert(rest, name)
                seen[name] = true
            end
        end
    end
    local sym = symbol or (#rest > 1 and "stay" or nil)
    for _, name in ipairs(rest) do
        psc.add(cs, { name = name, tip = completion_tip(name), symbol = sym })
    end
end

local info = psc.manifest and psc.manifest.info or {}

if psc.eq(cmd1, "add") then
    -- Installable remotely, not installed locally, and not typed yet
    local rest = {}
    for _, name in ipairs(d.remote or {}) do
        if not psc.typed_unknown(name) and not psc.contains(d.list, name) then
            table.insert(rest, name)
        end
    end
    local symbol = #rest > 1 and "stay" or nil
    for _, name in ipairs(rest) do
        psc.add(cs, { name = name, tip = completion_tip(name), symbol = symbol })
    end
elseif psc.contains({ "rm", "update", "info" }, cmd1) then
    add_completions(true)
elseif psc.eq(cmd1, "alias") then
    -- --reset is invalid inside add/rm; drop the bubbled-up alias-level --reset
    if psc.eq(cmd2, "add") then
        if #unknown > 0 then
            return psc.concat(cs, without_reset(completions))
        end
        for _, name in ipairs(d.list or {}) do
            psc.add(cs, { name = name, tip = render_tip(info.alias and info.alias.add.tip, { completion = name }) })
        end
        return psc.concat(cs, without_reset(completions))
    elseif psc.eq(cmd2, "rm") then
        if #unknown > 0 then
            local target = unknown[1]
            local typed = {}
            for i = 2, #unknown do
                typed[unknown[i]] = true
            end
            local rest = {}
            for _, a in ipairs((d.alias and d.alias[target]) or {}) do
                if not typed[a] then
                    table.insert(rest, a)
                end
            end
            local symbol = #rest > 2 and "stay" or nil
            local tip = render_tip(info.alias and info.alias.rm.tip_v, {})
            for _, a in ipairs(rest) do
                -- Use repeat 99 to explicitly bypass the engine filter
                psc.add(cs, { name = a, tip = tip, symbol = symbol, repeat_count = 99 })
            end
            return psc.concat(cs, without_reset(completions))
        end
        add_completions(false, "switch")
        return psc.concat(cs, without_reset(completions))
    end
elseif psc.eq(cmd1, "config") then
    -- config language follows the system language and can't be reset; drop the bubbled-up --reset
    if psc.eq(psc.cmds[3], "language") then
        return psc.concat(cs, without_reset(completions))
    end
elseif psc.eq(cmd1, "completion") then
    -- completion's --reset is per-level: drop the static one, add a dynamic tip for the current level
    local function completion_join(reset_tip)
        if reset_tip then
            psc.add(cs, { name = "--reset", tip = render_tip(reset_tip, {}), symbol = "stay" })
        end
        local static = {}
        for _, item in ipairs(completions) do
            if item.name ~= "--reset" then
                table.insert(static, item)
            end
        end
        return psc.concat(cs, static)
    end
    if #unknown >= 3 then
        return completion_join(nil)
    end
    if #unknown == 0 then
        add_completions(false, "switch")
        return psc.merge(cs)
    end
    local target = unknown[1]
    if not psc.contains(d.remote or {}, target) then
        return completion_join(nil)
    end
    local cfg = psc.json(d.completions .. "/" .. target .. "/config.json")
    local lang = target_language(target, cfg)
    local json = psc.json(d.completions .. "/" .. target .. "/language/" .. lang .. ".json")
    if #unknown == 1 then
        psc.add(cs, {
            name = "language",
            tip = render_tip(info.completion and info.completion.language.tip, { completion = target }),
            symbol = "switch"
        })
        psc.add(cs, {
            name = "enable_tip",
            tip = render_tip(info.completion and info.completion.enable_tip.tip, { completion = target }),
            symbol = "switch"
        })
        psc.add(cs, {
            name = "enable_tip_usage",
            tip = render_tip(info.completion and info.completion.enable_tip_usage.tip, { completion = target }),
            symbol = "switch"
        })
        psc.add(cs, {
            name = "enable_tip_example",
            tip = render_tip(info.completion and info.completion.enable_tip_example.tip, { completion = target }),
            symbol = "switch"
        })
        -- enable_hooks is always settable; offered only when config.json declares hooks
        if cfg and cfg.hooks ~= nil then
            local tip = render_tip(info.completion and info.completion.enable_hooks.tip, { completion = target })
            psc.add(cs, { name = "enable_hooks", tip = (tip:gsub("<@%w+>", "")), symbol = "switch" })
        end
        for _, c in ipairs((json and json.config) or {}) do
            local sym = c.values and "switch" or nil
            local tip = (psc.join(c.tip, "\n") or ""):gsub("<@%w+>", "")
            psc.add(cs, { name = c.name, tip = tip, symbol = sym })
        end
        return completion_join(info.completion and info.completion.reset_name)
    end
    local item = unknown[2]
    if psc.eq(item, "language") then
        for _, la in ipairs((cfg and cfg.language) or {}) do
            psc.add(cs,
                { name = la, tip = render_tip(info.completion and info.completion.language.tip_v, { language = la }) })
        end
    elseif item:match("^enable_") then
        psc.add(cs, { name = "0", tip = render_tip(info.set_value, { value = "0" }) })
        psc.add(cs, { name = "1", tip = render_tip(info.set_value, { value = "1" }) })
    else
        local c = nil
        for _, x in ipairs((json and json.config) or {}) do
            if x.name == item then
                c = x
                break
            end
        end
        if c and c.values then
            for _, v in ipairs(c.values) do
                psc.add(cs, { name = v, tip = render_tip(info.set_value, { value = v }) })
            end
        end
    end
    -- --reset tip differs by key kind (special key vs manifest config key); enumerated explicitly
    local special_keys = { "language", "enable_tip", "enable_tip_usage", "enable_tip_example", "enable_hooks" }
    local reset_tip
    if psc.contains(special_keys, item) then
        reset_tip = info.completion and info.completion.reset_special
    else
        reset_tip = info.completion and info.completion.reset_manifest
    end
    return completion_join(reset_tip)
end
return psc.concat(cs, static_items)
