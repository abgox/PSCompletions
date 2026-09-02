local function add_packages()
    local data = psc.run({ "uv", "pip", "list", "--format", "json" }, { format = "json" })
    if data then
        for _, pkg in ipairs(data) do
            if pkg.name then psc.add({ name = pkg.name, tip = pkg.version or "" }) end
        end
        return
    end
    -- fallback: pyproject.toml dependencies
    local toml = psc.toml("pyproject.toml")
    if toml and toml.project and toml.project.dependencies then
        for _, dep in ipairs(toml.project.dependencies) do
            local n = dep:match("^([%w%-%_]+)")
            if n then psc.add({ name = n, tip = dep }) end
        end
    end
end

local function add_pythons()
    for _, line in ipairs(psc.run({ "uv", "python", "list" }) or {}) do
        local v = line:match("^(cpython%S*)") or line:match("^(%d+%.%d+%.%d+)")
        if v then psc.add({ name = v, tip = line }) end
    end
end

psc.on({
    { option = "--with" },
    { command = { "pip", "uninstall" }, multiple = true },
    { command = { "pip", "show" } },
    { command = "remove", multiple = true },
    { command = "run" }
}, add_packages)

psc.on({ option = "--python" }, add_pythons)
