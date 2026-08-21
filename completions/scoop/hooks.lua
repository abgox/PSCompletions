if psc.current.option_like or #psc.cmds < 1 then
    return completions
end

local function scoop_config()
    local root = psc.env("SCOOP")
    local home = psc.env("USERPROFILE") or psc.env("HOME")
    if root then
        for _, p in ipairs({ root .. "/config.json", home .. "/.config/scoop/config.json" }) do
            if psc.exist(p) then
                return psc.json(p)
            end
        end
    end
    local cfg = {}
    for _, line in ipairs(psc.run({ "scoop", "config" }, { shell = true }) or {}) do
        local k, v = line:gsub("\27%[[%d;]*m", ""):match("^(%S+)%s*:%s*(.+)$")
        if k then
            cfg[k] = v
        end
    end
    return cfg
end

local function manifest_tip(c)
    if not c then
        return ""
    end
    local lines = {}
    table.insert(lines, "version:  " .. tostring(c.version or ""))
    local category = nil
    if c.psmodule then
        category = "psmodule"
    elseif c.font then
        category = "font"
    end
    if category then
        table.insert(lines, "category: " .. category)
    end
    if c.homepage then
        table.insert(lines, "homepage: " .. c.homepage)
    end
    local persistence = {}
    if c.link or psc.contains(c.pre_install, "A%-New%-Link", { pattern = true }) then
        table.insert(persistence, "link")
    end
    -- `persist` may be a single path (string) or a list (array); next() only works on tables.
    if type(c.persist) == "table" and next(c.persist) ~= nil then
        table.insert(persistence, "persist")
    end
    if #persistence > 0 then
        table.insert(lines, "persistence: " .. psc.join(persistence, ", "))
    end
    if c.admin then
        table.insert(lines, "permissions: admin")
    end
    if c.description then
        table.insert(lines, "-----")
        table.insert(lines, (psc.join(c.description, "\n"):gsub(" | ", "\n")))
    end
    return psc.join(lines, "\n")
end

local function bucket_manifests(buckets_dir, exclude, enable_tip)
    local entries = {}
    local paths = {}
    for _, b in ipairs(psc.ls(buckets_dir) or {}) do
        if b.is_dir and not psc.contains(exclude, b.name) then
            for _, m in ipairs(psc.glob(buckets_dir .. "/" .. b.name .. "/bucket/**/*.json") or {}) do
                table.insert(entries, { bucket = b.name, path = m })
                table.insert(paths, m)
            end
        end
    end
    local manifests = {}
    if enable_tip then
        manifests = psc.json_batch(paths)
    end
    return entries, manifests
end

local function add_bucket_apps(cs, entries, manifests, enable_tip, installed)
    for _, e in ipairs(entries) do
        local name = e.path:match("([^/\\]+)%.json$")
        if name and name ~= "scoop" and not (installed and installed[name]) then
            local app = e.bucket .. "/" .. name
            if not psc.typed(app) then
                local tip = ""
                if enable_tip then tip = manifest_tip(manifests[e.path]) end
                psc.add(cs, { name = app, tip = tip, symbol = "stay" })
            end
        end
    end
end

local function installed_apps(apps_dirs, root)
    local candidates = {}
    for _, d in ipairs(apps_dirs) do
        for _, e in ipairs(psc.ls(d) or {}) do
            if e.is_dir and e.name ~= "scoop" and not psc.typed_unknown(e.name) then
                table.insert(candidates, { dir = d, name = e.name })
            end
        end
    end
    local paths = {}
    for _, en in ipairs(candidates) do
        table.insert(paths, en.dir .. "/" .. en.name .. "/current/manifest.json")
        table.insert(paths, en.dir .. "/" .. en.name .. "/current/install.json")
    end
    local jsons = psc.json_batch(paths)
    -- Only a dir with a manifest counts as installed; a leftover dir after a failed install has no manifest.
    local entries = {}
    for _, en in ipairs(candidates) do
        if jsons[en.dir .. "/" .. en.name .. "/current/manifest.json"] then
            table.insert(entries, en)
        end
    end
    local cand_paths = {}
    for _, en in ipairs(entries) do
        local i = jsons[en.dir .. "/" .. en.name .. "/current/install.json"]
        if i and i.bucket and root then
            local app1 = en.name:match("^([^%.]+)")
            table.insert(cand_paths,
                root ..
                "/buckets/" .. i.bucket .. "/bucket/" .. en.name:sub(1, 1) .. "/" .. app1 .. "/" .. en.name .. ".json")
            table.insert(cand_paths, root .. "/buckets/" .. i.bucket .. "/bucket/" .. en.name .. ".json")
        end
    end
    local cand_map = psc.json_batch(cand_paths)
    return entries, jsons, cand_map
end

local function installed_tip(name, c, i, root, cand_map)
    if not c then
        return name
    end
    local lines = {}
    if i and i.bucket then
        table.insert(lines, "bucket:   " .. i.bucket)
    end
    local v = tostring(c.version or "")
    if i and i.bucket and root then
        local app1 = name:match("^([^%.]+)")
        local cand1 = root ..
            "/buckets/" .. i.bucket .. "/bucket/" .. name:sub(1, 1) .. "/" .. app1 .. "/" .. name .. ".json"
        local cand2 = root .. "/buckets/" .. i.bucket .. "/bucket/" .. name .. ".json"
        local bm = cand_map and (cand_map[cand1] or cand_map[cand2]) or nil
        if bm and bm.version and tostring(bm.version) ~= tostring(c.version) then
            v = v .. " (" .. tostring(bm.version) .. ")"
        end
    end
    table.insert(lines, "version:  " .. v)
    local category = nil
    if c.psmodule then
        category = "psmodule"
    elseif c.font then
        category = "font"
    end
    if category then
        table.insert(lines, "category: " .. category)
    end
    if c.homepage then
        table.insert(lines, "homepage: " .. c.homepage)
    end
    local persistence = {}
    if c.link or psc.contains(c.pre_install, "A%-New%-Link", { pattern = true }) then
        table.insert(persistence, "link")
    end
    -- `persist` may be a single path (string) or a list (array); next() only works on tables.
    if type(c.persist) == "table" and next(c.persist) ~= nil then
        table.insert(persistence, "persist")
    end
    if #persistence > 0 then
        table.insert(lines, "persistence: " .. psc.join(persistence, ", "))
    end
    if c.admin then
        table.insert(lines, "permissions: admin")
    end
    if c.description then
        table.insert(lines, "-----")
        table.insert(lines, (psc.join(c.description, "\n"):gsub(" | ", "\n")))
    end
    return psc.join(lines, "\n")
end

local cs = {}

local config = scoop_config()
local root = psc.env("SCOOP") or config.root_path
if not root then
    return completions
end
local global = psc.env("SCOOP_GLOBAL") or config.global_path

local apps_dirs = {}
if psc.exist(root .. "/apps") then
    table.insert(apps_dirs, root .. "/apps")
end
if global and psc.exist(global .. "/apps") then
    table.insert(apps_dirs, global .. "/apps")
end

local buckets_dir = root .. "/buckets"

local function list_bucket_dirs()
    local out = {}
    for _, b in ipairs(psc.ls(buckets_dir) or {}) do
        if b.is_dir then
            table.insert(out, b.name)
        end
    end
    return out
end

local function list_app_dirs()
    local out = {}
    for _, d in ipairs(apps_dirs) do
        for _, e in ipairs(psc.ls(d) or {}) do
            if e.is_dir and e.name ~= "scoop" and psc.exist(d .. "/" .. e.name .. "/current/manifest.json") then
                table.insert(out, e.name)
            end
        end
    end
    return out
end

local cmd1, cmd2 = psc.cmds[1], psc.cmds[2]

if not cmd1 then
    if #list_bucket_dirs() > 0 then
        psc.set_symbol("cat", "switch")
        psc.set_symbol("home", "switch")
    end
    if #list_app_dirs() > 0 then
        psc.set_symbol("depends", "switch")
        psc.set_symbol("prefix", "switch")
    end
elseif psc.eq(cmd1, "bucket") then
    if #list_bucket_dirs() > 0 then
        psc.set_symbol("rm", "switch")
    end
elseif psc.eq(cmd1, "config") then
    if next(config) ~= nil then
        psc.set_symbol("rm", "switch")
    end
end

if psc.eq(cmd1, "bucket") and psc.eq(cmd2, "rm") then
    for _, name in ipairs(list_bucket_dirs()) do
        psc.add(cs, { name = name })
    end
elseif psc.eq(cmd1, "install") then
    local last_token = psc.tokens[#psc.tokens]
    if not (last_token and psc.eq(last_token.name, "--arch")) then
        local exclude = {}
        for x in (psc.config.exclude_buckets or ""):gmatch("[^|]+") do
            table.insert(exclude, x)
        end
        local enable_tip = not (psc.config.enable_hooks_tip == 0)
        local entries, manifests = bucket_manifests(buckets_dir, exclude, enable_tip)
        local installed = {}
        for _, name in ipairs(list_app_dirs()) do
            installed[name] = true
        end
        add_bucket_apps(cs, entries, manifests, enable_tip, installed)
    end
elseif psc.contains({ "uninstall", "cleanup", "prefix", "update", "depends", "hold", "unhold" }, cmd1) then
    local entries, jsons, cand_map = installed_apps(apps_dirs, root)
    local want_held = psc.eq(cmd1, "unhold")
    local is_hold = psc.contains({ "hold", "unhold" }, cmd1)
    for _, en in ipairs(entries) do
        local base = en.dir .. "/" .. en.name .. "/current"
        local i = jsons[base .. "/install.json"]
        local include = true
        if is_hold then
            local held = (i and i.hold) == true
            include = (held == want_held)
        end
        if include then
            psc.add(cs,
                {
                    name = en.name,
                    tip = installed_tip(en.name, jsons[base .. "/manifest.json"], i, root, cand_map),
                    symbol = "stay"
                }
            )
        end
    end
elseif psc.contains({ "home", "info", "cat", "reset", "download", "virustotal" }, cmd1) then
    local exclude = {}
    for x in (psc.config.exclude_buckets or ""):gmatch("[^|]+") do
        table.insert(exclude, x)
    end
    local enable_tip = not (psc.config.enable_hooks_tip == 0)
    local entries, manifests = bucket_manifests(buckets_dir, exclude, enable_tip)
    add_bucket_apps(cs, entries, manifests, enable_tip)
elseif psc.eq(cmd1, "cache") then
    if #list_app_dirs() > 0 then
        psc.set_symbol("show", "switch")
    end
    if psc.eq(cmd2, "show") then
        local entries, jsons, cand_map = installed_apps(apps_dirs, root)
        for _, en in ipairs(entries) do
            local base = en.dir .. "/" .. en.name .. "/current"
            local i = jsons[base .. "/install.json"]
            psc.add(cs,
                {
                    name = en.name,
                    tip = installed_tip(en.name, jsons[base .. "/manifest.json"], i, root, cand_map),
                    symbol = "stay"
                }
            )
        end
    end
    if psc.eq(cmd2, "rm") then
        local cache_dirs = { root .. "/cache" }
        if config.cache_path then
            table.insert(cache_dirs, config.cache_path)
        end
        for _, cdir in ipairs(cache_dirs) do
            for _, f in ipairs(psc.ls(cdir) or {}) do
                local cache = f.name:match("^([^#]+#[^#]+)")
                if cache and not psc.typed_unknown(cache) then
                    psc.add(cs, { name = cache, tip = f.path, symbol = "stay" })
                end
            end
        end
    end
elseif psc.eq(cmd1, "config") and psc.eq(cmd2, "rm") then
    for k, v in pairs(config) do
        psc.add(cs, { name = k, tip = v })
    end
end

return psc.merge(cs)
