local function working_dir()
    for i, token in ipairs(psc.tokens) do
        if psc.eq(token.name, "--working-dir") then
            local value = psc.tokens[i + 1]
            if value and value.input and value.input ~= "" then
                return value.input
            end
            return psc.cwd
        end
    end
    return psc.cwd
end

local function project_json(name)
    return psc.json(psc.path(working_dir(), name))
end

local function add_command()
    psc.add(psc.mount_items({ "next" }))
end

local function add_locked_package()
    local lock = project_json("composer.lock") or {}
    for _, section in ipairs({ "packages", "packages-dev" }) do
        for _, package in ipairs(lock[section] or {}) do
            if package.name then
                psc.add({ name = package.name })
            end
        end
    end
end

local function add_required_package()
    local config = project_json("composer.json") or {}
    for _, section in ipairs({ "require", "require-dev" }) do
        local names = {}
        for name in pairs(config[section] or {}) do
            names[#names + 1] = name
        end
        table.sort(names)
        psc.add(psc.items(names))
    end
end

local function add_script()
    local config = project_json("composer.json") or {}
    local names = {}
    for name in pairs(config.scripts or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    psc.add(psc.items(names))
end

local function add_platform_package()
    local config = project_json("composer.json") or {}
    local names = {}
    for name in pairs(config.require or {}) do
        if name:match("^php$") or name:match("^ext%-") or name:match("^lib%-") or name:match("^composer%-") then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    psc.add(psc.items(names))
end

local function add_binary()
    local lines = psc.run({ "composer", "exec", "--list" }, { cwd = working_dir() }) or {}
    local listed = false
    for _, line in ipairs(lines) do
        if line:match("^Available binaries:") then
            listed = true
        elseif listed then
            local name = line:match("^%- (.+)$")
            if name then
                psc.add({ name = psc.trim(name) })
            end
        end
    end
end

local function add_config_key()
    local lines = psc.run({ "composer", "config", "--list" }, { cwd = working_dir() }) or {}
    for _, line in ipairs(lines) do
        local key = line:match("^%[([^%]]+)%]")
        if key then
            psc.add({ name = key })
        end
    end
end

psc.on({
    { command = "help" },
    { command = "global" },
}, add_command)

psc.on({
    { command = "show" },
    { command = "outdated" },
    { command = "depends" },
    { command = "prohibits" },
    { command = "reinstall" },
    { command = "upgrade" },
    { command = "bump" },
    { command = "suggests" },
    { command = "browse" },
    { option = "--ignore" },
}, add_locked_package)

psc.on({ command = "uninstall" }, add_required_package)

psc.on({ command = "run-script" }, add_script)

psc.on({ option = "--ignore-platform-req" }, add_platform_package)

psc.on({ command = "exec" }, add_binary)

psc.on({ command = "config" }, add_config_key)
