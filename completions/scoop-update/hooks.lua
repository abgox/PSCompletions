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

local function get_manifest_paths(root, bucket, app_name)
    local base = app_name:match("^([^%.]+)")
    return {
        psc.path(root, "buckets", bucket, "bucket", app_name:sub(1, 1), base, app_name .. ".json"),
        psc.path(root, "buckets", bucket, "bucket", app_name .. ".json")
    }
end

local function get_installed_apps(apps_dirs, root)
    local found = {}
    for _, apps_dir in ipairs(apps_dirs) do
        for _, entry in ipairs(psc.ls(apps_dir) or {}) do
            if entry.is_dir and entry.name ~= "scoop" then
                table.insert(found, { apps_dir = apps_dir, name = entry.name })
            end
        end
    end
    local json_paths = {}
    for _, app in ipairs(found) do
        local current = psc.path(app.apps_dir, app.name, "current")
        table.insert(json_paths, psc.path(current, "manifest.json"))
        table.insert(json_paths, psc.path(current, "install.json"))
    end
    local json_by_path = psc.json_batch(json_paths)
    local apps = {}
    for _, app in ipairs(found) do
        local current = psc.path(app.apps_dir, app.name, "current")
        if json_by_path[psc.path(current, "manifest.json")] then
            app.manifest = json_by_path[psc.path(current, "manifest.json")]
            app.install = json_by_path[psc.path(current, "install.json")]
            table.insert(apps, app)
        end
    end
    local bucket_paths = {}
    if root then
        for _, app in ipairs(apps) do
            if app.install and app.install.bucket then
                for _, path in ipairs(get_manifest_paths(root, app.install.bucket, app.name)) do
                    table.insert(bucket_paths, path)
                end
            end
        end
    end
    return apps, psc.json_batch(bucket_paths)
end

local function get_installed_tip(app, root, bucket_manifests)
    local manifest = app.manifest
    if not manifest then
        return app.name
    end
    local install = app.install
    local lines = {}
    if install and install.bucket then
        table.insert(lines, "bucket:   " .. install.bucket)
    end
    local v = tostring(manifest.version or "")
    if install and install.bucket and root then
        local bm = nil
        for _, path in ipairs(get_manifest_paths(root, install.bucket, app.name)) do
            bm = bucket_manifests[path]
            if bm and bm.version and tostring(bm.version) ~= tostring(manifest.version) then
                v = v .. " (" .. tostring(bm.version) .. ")"
                break
            end
        end
    end
    table.insert(lines, "version:  " .. v)
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

local function add_installed_apps()
    local root = get_root()
    local apps, bucket_manifests = get_installed_apps(get_apps_dir(), root)
    for _, app in ipairs(apps) do
        psc.add({
            name = app.name,
            tip = get_installed_tip(app, root, bucket_manifests)
        })
    end
end

psc.on({ multiple = true }, add_installed_apps)
