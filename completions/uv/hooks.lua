local function token_value(name)
    local tokens = psc.tokens or {}
    for i, t in ipairs(tokens) do
        if t.type == "option" and t.name == name and tokens[i + 1] then
            return tokens[i + 1].input
        end
    end
end

local function pyproject_path()
    local dir = token_value("--project") or token_value("--directory")
    if dir then
        return psc.path(dir, "pyproject.toml")
    end
    return "pyproject.toml"
end

local function add_packages()
    local argv = { "uv" }
    local dir = token_value("--directory")
    if dir then
        argv[#argv + 1] = "--directory"
        argv[#argv + 1] = dir
    end
    argv[#argv + 1] = "pip"
    argv[#argv + 1] = "list"
    argv[#argv + 1] = "--format"
    argv[#argv + 1] = "json"
    local data = psc.run(argv, { format = "json" })
    if type(data) ~= "table" then return end
    for _, pkg in ipairs(data) do
        if pkg.name then
            if pkg.version then
                psc.add({ name = pkg.name, tip = pkg.version })
            else
                psc.add({ name = pkg.name })
            end
        end
    end
end

local function add_project_deps()
    local data = psc.toml(pyproject_path())
    if not data then return end
    local seen = {}
    local function add(list)
        for _, dep in ipairs(list or {}) do
            if type(dep) == "string" then
                local name = dep:match("^%s*([%w%._%-]+)")
                if name and not seen[name] then
                    seen[name] = true
                    psc.add({ name = name })
                end
            end
        end
    end
    if data.project then
        add(data.project.dependencies)
    end
    for _, group in pairs(data["dependency-groups"] or {}) do
        add(group)
    end
end

local function add_pythons()
    for _, line in ipairs(psc.run({ "uv", "python", "list" }) or {}) do
        local v = line:match("^(cpython%S*)") or line:match("^(%d+%.%d+%.%d+)")
        if v then psc.add({ name = v, tip = line }) end
    end
end

-- uninstall takes installed keys only, so ask for the installed subset instead of the full list
local function add_installed_pythons()
    for _, line in ipairs(psc.run({ "uv", "python", "list", "--only-installed" }) or {}) do
        local v = line:match("^(cpython%S*)") or line:match("^(%d+%.%d+%.%d+)")
        if v then psc.add({ name = v, tip = line }) end
    end
end

-- `uv tool list` prints "name vX.Y.Z" followed by the executables the tool provides
local function add_tools()
    for _, line in ipairs(psc.run({ "uv", "tool", "list" }) or {}) do
        local name = line:match("^([^%s]+) v")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { command = { "pip", "uninstall" }, multiple = true },
    { command = { "pip", "show" } }
}, add_packages)

psc.on({ command = "remove", multiple = true }, add_project_deps)

psc.on({
    { option = "--python" },
    { command = { "python", "install" }, multiple = true },
    { command = { "python", "upgrade" }, multiple = true },
    { command = { "python", "pin" } },
    { command = { "python", "find" } }
}, add_pythons)

psc.on({ command = { "python", "uninstall" }, multiple = true }, add_installed_pythons)

psc.on({
    { command = { "tool", "run" } },
    { command = { "tool", "uninstall" }, multiple = true },
    { command = { "tool", "upgrade" },   multiple = true },
    { command = { "tool", "audit" },     multiple = true }
}, add_tools)

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
