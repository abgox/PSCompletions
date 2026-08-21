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

local cs = {}

local last_token = psc.tokens[#psc.tokens]
if last_token and psc.eq(last_token.name, "--arch") then
    return completions
end

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

return psc.merge(cs)
