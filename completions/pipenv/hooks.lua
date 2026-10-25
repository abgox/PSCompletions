local EXCLUDED_SECTIONS = {
    ["build-system"] = true,
    ["pipenv"] = true,
    ["requires"] = true,
    ["scripts"] = true,
    ["source"] = true,
}

local pipfile_cache

local function pipfile_path()
    local override = psc.env("PIPENV_PIPFILE")
    if override and override ~= "" then
        return override
    end
    -- pipenv searches upward for the project file, so a subdirectory must find its parent Pipfile.
    local dir = psc.cwd
    while dir and dir ~= "" do
        local candidate = psc.path(dir, "Pipfile")
        if psc.exist(candidate) then
            return candidate
        end
        dir = dir:match("^(.*)[/\\][^/\\]+$")
    end
    return nil
end

local function load_pipfile()
    if pipfile_cache == nil then
        pipfile_cache = psc.toml(pipfile_path() or {}) or false
    end
    return pipfile_cache or nil
end

-- Mirrors Pipfile.get_package_categories: every top-level table except the non-category sections.
local function category_names(pipfile)
    local names = { "packages", "dev-packages" }
    local custom = {}
    for key in pairs(pipfile) do
        if
            type(key) == "string"
            and key ~= "packages"
            and key ~= "dev-packages"
            and not EXCLUDED_SECTIONS[key]
        then
            custom[#custom + 1] = key
        end
    end
    table.sort(custom)
    for _, key in ipairs(custom) do
        names[#names + 1] = key
    end
    return names
end

local function add_packages()
    local pipfile = load_pipfile()
    if not pipfile then
        return
    end
    local seen = {}
    for _, category in ipairs(category_names(pipfile)) do
        local section = pipfile[category]
        if type(section) == "table" then
            for name in pairs(section) do
                if type(name) == "string" and name ~= "" and not seen[name] then
                    seen[name] = true
                    psc.add({
                        name = name,
                        tip = {
                            ["en-US"] = "Pipfile " .. category,
                            ["zh-CN"] = "Pipfile 分类: " .. category,
                        },
                    })
                end
            end
        end
    end
end

local function add_categories()
    local pipfile = load_pipfile()
    if not pipfile then
        return
    end
    for _, name in ipairs(category_names(pipfile)) do
        psc.add({
            name = name,
            tip = { ["en-US"] = "Pipfile category", ["zh-CN"] = "Pipfile 分类" },
        })
    end
end

local function add_sources()
    local pipfile = load_pipfile()
    if not pipfile or type(pipfile.source) ~= "table" then
        return
    end
    for _, source in ipairs(pipfile.source) do
        if type(source) == "table" and type(source.name) == "string" and source.name ~= "" then
            psc.add({
                name = source.name,
                tip = { ["en-US"] = "Pipfile source", ["zh-CN"] = "Pipfile 源" },
            })
        end
    end
end

local function add_scripts()
    local pipfile = load_pipfile()
    if not pipfile or type(pipfile.scripts) ~= "table" then
        return
    end
    local names = {}
    for name in pairs(pipfile.scripts) do
        if type(name) == "string" and name ~= "" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        psc.add({
            name = name,
            tip = { ["en-US"] = "Pipfile script", ["zh-CN"] = "Pipfile 脚本" },
        })
    end
end

psc.on({
    { command = "uninstall", multiple = true },
    { command = "upgrade",   multiple = true },
    { command = "update",    multiple = true },
}, add_packages)

psc.on({
    { command = "install",      option = "--categories" },
    { command = "upgrade",      option = "--categories" },
    { command = "uninstall",    option = "--categories" },
    { command = "lock",         option = "--categories" },
    { command = "update",       option = "--categories" },
    { command = "sync",         option = "--categories" },
    { command = "check",        option = "--categories" },
    { command = "requirements", option = "--categories" },
}, add_categories)

psc.on({
    { command = "install", option = "--index" },
    { command = "upgrade", option = "--index" },
    { command = "update",  option = "--index" },
}, add_sources)

psc.on({ command = "run" }, add_scripts)
