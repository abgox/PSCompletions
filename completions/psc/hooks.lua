---@diagnostic disable-next-line: undefined-field
local data = psc._data or {}
---@diagnostic disable-next-line: undefined-field
local info = psc.manifest.info or {}

local function get_completion_tip(name)
    local meta = data.meta and data.meta[name]
    if not meta then
        return
    end
    local lang = psc.config.language or "en-US"
    local c = meta[lang]
    if not c then
        return
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

local function render_tip(lines, vars)
    -- lines may be string or array; normalize via psc.join
    if type(lines) == "string" then
        lines = { lines }
    end
    local out = {}
    for _, line in ipairs(lines or {}) do
        for k, v in pairs(vars) do
            line = line:gsub("{{ %$" .. k .. " }}", tostring(v))
        end
        table.insert(out, line)
    end
    return psc.join(out, "\n")
end

local function rm_reset()
    for i = #completions, 1, -1 do
        if completions[i].name == "--reset" then
            table.remove(completions, i)
            break
        end
    end
end

local function add_installed_completions()
    for _, e in ipairs(psc.ls(data.completions) or {}) do
        if e.is_dir then
            psc.add({ name = e.name, tip = get_completion_tip(e.name) })
        end
    end
end

local function add_uninstalled_completions()
    for _, name in ipairs(data.remote or {}) do
        if not psc.contains(data.list, name) then
            psc.add({ name = name, tip = get_completion_tip(name) })
        end
    end
end

psc.on({ command = "add", multiple = true }, add_uninstalled_completions)

psc.on({ command = { "alias", "add" }, multiple = true }, function()
    local tokens_length = #psc.tokens
    if tokens_length > 3 then
        rm_reset()
        return
    end
    if tokens_length == 2 then
        add_installed_completions()
        return
    end
end)

psc.on({ command = { "alias", "rm" }, multiple = true }, function()
    local tokens_length = #psc.tokens
    if tokens_length == 2 then
        add_installed_completions()
        return
    end
    if tokens_length >= 3 then
        local target = psc.tokens[3].name
        local tip = render_tip(info.alias.rm.tip_v, {})
        for _, a in ipairs(data.alias[target] or {}) do
            psc.add({ name = a, tip = tip, repeat_count = 2 })
        end
        return
    end
end)

psc.on({ command = "completion", multiple = true }, function()
    local tokens_length = #psc.tokens
    if tokens_length >= 4 then
        rm_reset()
        return
    end
    if tokens_length == 1 then
        add_installed_completions()
        return
    end
    local target = psc.tokens[2].name
    local cfg = psc.json(psc.path(data.completions, target, "config.json"))
    if not cfg then
        return
    end
    local json = psc.json(psc.path(data.completions, target, "language", psc.config.language .. ".json"))
    if not json then
        json = psc.json(psc.path(data.completions, target, "language", cfg.language[1] .. ".json"))
    end
    if tokens_length == 2 then
        psc.add({
            name = "language",
            tip = render_tip(info.completion.language.tip, { completion = target })
        })
        psc.add({
            name = "enable_tip",
            tip = render_tip(info.completion.enable_tip.tip, { completion = target })
        })
        psc.add({
            name = "enable_tip_usage",
            tip = render_tip(info.completion.enable_tip_usage.tip, { completion = target })
        })
        psc.add({
            name = "enable_tip_example",
            tip = render_tip(info.completion.enable_tip_example.tip, { completion = target })
        })
        if target ~= "psc" and psc.exist(psc.path(data.completions, target, "hooks.lua")) then
            local tip = render_tip(info.completion.enable_hooks.tip, { completion = target })
            psc.add({ name = "enable_hooks", tip = (tip:gsub("<@%w+>", "")) })
        end
        for _, c in ipairs((json and json.config) or {}) do
            local tip = (psc.join(c.tip, "\n") or ""):gsub("<@%w+>", "")
            psc.add({ name = c.name, tip = tip })
        end
        return
    end
    if tokens_length == 3 then
        local config_name = psc.tokens[3].name
        if psc.eq(config_name, "language") then
            for _, lang in ipairs(cfg.language or {}) do
                psc.add(
                    {
                        name = lang,
                        tip = render_tip(info.completion.language.tip_v,
                            { language = lang })
                    })
            end
        elseif config_name:find("^enable") or config_name:find("^disable") then
            psc.add({ name = "0", tip = render_tip(info.set_value, { value = "0" }) })
            psc.add({ name = "1", tip = render_tip(info.set_value, { value = "1" }) })
        else
            local c = nil
            for _, x in ipairs((json and json.config) or {}) do
                if psc.eq(config_name, x.name) then
                    c = x
                    break
                end
            end
            if c and c.values then
                for _, v in ipairs(c.values) do
                    psc.add({ name = v, tip = render_tip(info.set_value, { value = v }) })
                end
            end
        end
    end
end)

psc.on({ command = { "config", "core", "language" } }, rm_reset)

psc.on({
    { command = "update", multiple = true },
    { command = "info",   multiple = true },
    { command = "rm",     multiple = true }
}, add_installed_completions)
