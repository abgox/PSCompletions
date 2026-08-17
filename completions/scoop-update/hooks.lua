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
        local k, v = line:match("^(%S+)%s*:%s*(.+)$")
        if k then
            cfg[k] = v
        end
    end
    return cfg
end

local function installed_tip(apps_dir, app, root)
    local base = apps_dir .. "/" .. app .. "/current"
    local c = psc.json(base .. "/manifest.json")
    if not c then
        return app
    end
    local i = psc.json(base .. "/install.json")
    local lines = {}
    if i and i.bucket then
        table.insert(lines, "bucket:   " .. i.bucket)
    end
    local v = tostring(c.version or "")
    if i and i.bucket and root then
        local app1 = app:match("^([^%.]+)")
        local cand1 = root ..
            "/buckets/" .. i.bucket .. "/bucket/" .. app:sub(1, 1) .. "/" .. app1 .. "/" .. app .. ".json"
        local cand2 = root .. "/buckets/" .. i.bucket .. "/bucket/" .. app .. ".json"
        local bm = psc.json(cand1) or psc.json(cand2)
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

if psc.current.option_like then
    return completions
end

local config = scoop_config()
local root = psc.env("SCOOP") or config.root_path
if not root then
    return completions
end

local global = psc.env("SCOOP_GLOBAL") or config.global_path

local apps_dirs = {}
if psc.exist(root .. "/apps") then table.insert(apps_dirs, root .. "/apps") end
if global and psc.exist(global .. "/apps") then table.insert(apps_dirs, global .. "/apps") end

for _, d in ipairs(apps_dirs) do
    for _, e in ipairs(psc.ls(d) or {}) do
        if e.is_dir and not psc.typed_unknown(e.name) then
            psc.add(cs, { name = e.name, tip = installed_tip(d, e.name, root), symbol = "stay" })
        end
    end
end

return psc.merge(cs)
