if psc.platform ~= "windows" or psc.typing.option_like then
    return
end

local scoop_config_cache = nil

local function get_scoop_config()
    if scoop_config_cache then
        return scoop_config_cache
    end
    local root = psc.env("SCOOP")
    local home = psc.env("USERPROFILE") or psc.env("HOME")
    if root then
        for _, path in ipairs({ psc.path(root, "config.json"), psc.path(home, ".config", "scoop", "config.json") }) do
            if psc.exist(path) then
                local cfg = psc.json(path) or {}
                scoop_config_cache = cfg
                return cfg
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
    scoop_config_cache = cfg
    return cfg
end

local function get_root()
    local config = get_scoop_config()
    return psc.env("SCOOP") or config.root_path
end

local function get_buckets_dir()
    local root = get_root()
    if root then
        return psc.path(root, "buckets")
    end
end

local function get_apps_dir()
    local config = get_scoop_config()
    local root = psc.env("SCOOP") or config.root_path
    if not root then
        return {}
    end
    local global = psc.env("SCOOP_GLOBAL") or config.global_path
    local apps_dirs = {}
    if psc.exist(psc.path(root, "apps")) then
        table.insert(apps_dirs, psc.path(root, "apps"))
    end
    if global and psc.exist(psc.path(global, "apps")) then
        table.insert(apps_dirs, psc.path(global, "apps"))
    end
    return apps_dirs
end

local function get_manifests()
    local exclude = {}
    for x in psc.config.exclude_buckets:gmatch("[^|]+") do
        table.insert(exclude, x)
    end
    local entries = {}
    local paths = {}
    local buckets_dir = get_buckets_dir()
    for _, bucket in ipairs(psc.ls(buckets_dir) or {}) do
        if bucket.is_dir and not psc.contains(exclude, bucket.name) then
            for _, path in ipairs(psc.glob(psc.path(buckets_dir, bucket.name, "bucket", "**/*.json")) or {}) do
                table.insert(entries, { bucket = bucket.name, path = path })
                table.insert(paths, path)
            end
        end
    end
    local manifests = {}
    if psc.config.enable_tip then
        manifests = psc.json_batch(paths)
    end
    return entries, manifests
end

local function get_manifest_tip(manifest)
    if not manifest then
        return ""
    end
    local lines = {}
    table.insert(lines, "version:  " .. tostring(manifest.version or ""))
    local category = nil
    if manifest.psmodule then
        category = "psmodule"
    elseif manifest.font then
        category = "font"
    end
    if category then
        table.insert(lines, "category: " .. category)
    end
    if manifest.homepage then
        table.insert(lines, "homepage: " .. manifest.homepage)
    end
    local persistence = {}
    if manifest.link or psc.contains(manifest.pre_install, "A%-New%-Link", { pattern = true }) then
        table.insert(persistence, "link")
    end
    if manifest.persist then
        table.insert(persistence, "persist")
    end
    if #persistence > 0 then
        table.insert(lines, "persistence: " .. psc.join(persistence, ", "))
    end
    if manifest.admin then
        table.insert(lines, "permissions: admin")
    end
    if manifest.description then
        table.insert(lines, "-----")
        table.insert(lines, (psc.join(manifest.description, "\n"):gsub(" | ", "\n")))
    end
    return psc.join(lines, "\n")
end

local function add_uninstalled_apps()
    local installed = {}
    for _, apps_dir in ipairs(get_apps_dir()) do
        for _, entry in ipairs(psc.ls(apps_dir) or {}) do
            if entry.is_dir and entry.name ~= "scoop" and psc.exist(psc.path(apps_dir, entry.name, "current", "manifest.json")) then
                installed[entry.name] = true
            end
        end
    end
    local entries, manifests = get_manifests()
    for _, entry in ipairs(entries) do
        local name = entry.path:match("([^/\\]+)%.json$")
        if name and name ~= "scoop" and not (installed and installed[name]) then
            local app = entry.bucket .. "/" .. name
            if not psc.token({ name = app, type = "unknown" }) and not psc.token({ name = name, type = "unknown" }) then
                local tip = ""
                if psc.config.enable_tip then
                    tip = get_manifest_tip(manifests[entry.path])
                end
                psc.add({ name = app, tip = tip })
            end
        end
    end
end

psc.on({ multiple = true }, add_uninstalled_apps)
