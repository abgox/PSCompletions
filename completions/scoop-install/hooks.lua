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

local function manifest_tip(path)
    local c = psc.json(path)
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

local cs = {}

if psc.current.option_like then
    return completions
end

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

local installed = {}
local apps_dirs = {}
if psc.exist(root .. "/apps") then
    table.insert(apps_dirs, root .. "/apps")
end
if global and psc.exist(global .. "/apps") then
    table.insert(apps_dirs, global .. "/apps")
end

for _, d in ipairs(apps_dirs) do
    for _, e in ipairs(psc.ls(d) or {}) do
        installed[e.name] = true
    end
end

local exclude_buckets = {}
local buckets_dir = root .. "/buckets"
local enable_tip = not (psc.config.enable_hooks_tip == 0)

for b in (psc.config.exclude_buckets or ""):gmatch("[^|]+") do
    table.insert(exclude_buckets, b)
end

for _, b in ipairs(psc.ls(buckets_dir) or {}) do
    if b.is_dir then
        local excluded = false
        for _, x in ipairs(exclude_buckets) do
            if b.name == x then
                excluded = true
                break
            end
        end
        if not excluded then
            for _, m in ipairs(psc.glob(buckets_dir .. "/" .. b.name .. "/bucket/**/*.json") or {}) do
                local name = m:match("([^/\\]+)%.json$")
                if name and name ~= "scoop" and not installed[name] then
                    local app = b.name .. "/" .. name
                    if not psc.typed(app) then
                        local tip = ""
                        if enable_tip then
                            tip = manifest_tip(m)
                        end
                        psc.add(cs, { name = app, tip = tip, symbol = "stay" })
                    end
                end
            end
        end
    end
end

return psc.merge(cs)
