local function add_packages()
    local lines = psc.run({ "poetry", "show", "--no-ansi" }) or {}
    if #lines > 0 then
        for _, line in ipairs(lines) do
            local name = line:match("^(%S+)")
            if name then psc.add({ name = name, tip = line }) end
        end
        return
    end
    -- fallback: pyproject.toml dependencies
    local data = psc.toml("pyproject.toml")
    if not data then return end
    local deps = {}
    if data.tool and data.tool.poetry and data.tool.poetry.dependencies then
        deps = data.tool.poetry.dependencies
    elseif data.project and data.project.dependencies then
        for _, dep in ipairs(data.project.dependencies) do
            local n = dep:match("^([%w%-%_]+)")
            if n then psc.add({ name = n, tip = dep }) end
        end
        return
    end
    for k, v in pairs(deps) do
        if k ~= "python" then psc.add({ name = k, tip = tostring(v) }) end
    end
end

local function add_envs()
    for _, line in ipairs(psc.run({ "poetry", "env", "list", "--no-ansi" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_scripts()
    -- pyproject.toml scripts
    local data = psc.toml("pyproject.toml")
    if data and data.tool and data.tool.poetry and data.tool.poetry.scripts then
        for k, v in pairs(data.tool.poetry.scripts) do
            psc.add({ name = k, tip = tostring(v) })
        end
    end
    -- also list files? poetry run can run any command
end

psc.on({
    { command = "remove", multiple = true },
    { command = "show" }
}, add_packages)

psc.on({
    { command = { "env", "remove" } },
    { command = { "env", "use" } }
}, add_envs)

psc.on({ command = "run" }, add_scripts)
