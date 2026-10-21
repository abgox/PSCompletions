local function add_packages()
    for _, line in ipairs(psc.run({ "dotnet", "list", "package" }) or {}) do
        local name = line:match("^%s*>?%s*([%w%.%-_]+)%s+[%d%.]")
        if not name then
            name = line:match("^%s*([%w%.%-_]+)%s+[%d%.]+")
        end
        if name and name ~= "Project" and name ~= "TopLevelPackage" and not name:match("^%-") then
            psc.add({ name = name, tip = psc.trim(line) })
        end
    end
end

local function add_tools()
    local seen = {}
    for _, scope in ipairs({ "--global", "--local" }) do
        for _, line in ipairs(psc.run({ "dotnet", "tool", "list", scope }) or {}) do
            local name = line:match("^(%S+)%s+%S+")
            if name and name ~= "Package" and not name:match("^%-") and not seen[name] then
                seen[name] = true
                psc.add({ name = name, tip = psc.trim(line) })
            end
        end
    end
end

local function add_tool_commands()
    for _, line in ipairs(psc.run({ "dotnet", "tool", "list", "--local" }) or {}) do
        local name = line:match("(%S+)$")
        if name and name ~= "Commands" and not name:match("^%-") then
            psc.add({ name = name, tip = psc.trim(line) })
        end
    end
end

local function add_workloads_search()
    for _, line in ipairs(psc.run({ "dotnet", "workload", "search" }) or {}) do
        local id = line:match("^(%S+)")
        if id and id ~= "Workload" and not id:match("^%-") then
            psc.add({ name = id, tip = psc.trim(line) })
        end
    end
end

local function add_workloads_installed()
    for _, line in ipairs(psc.run({ "dotnet", "workload", "list" }) or {}) do
        local id = line:match("^(%S+)%s+%S+%s+%S+")
        if id and id ~= "Installed" and id ~= "Workload" and not id:match("^%-") then
            psc.add({ name = id, tip = psc.trim(line) })
        end
    end
end

local function add_templates()
    for _, line in ipairs(psc.run({ "dotnet", "new", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "Template" and not name:match("^%-") and not name:match("^%-%-") then
            psc.add({ name = name, tip = psc.trim(line) })
        end
    end
end

local function add_template_packages()
    local started = false
    for _, line in ipairs(psc.run({ "dotnet", "new", "uninstall" }) or {}) do
        if line:match("Currently installed items:") then
            started = true
        elseif started and line:match("^%s*$") then
            break
        elseif started then
            local name = line:match("^%s*(%S+)")
            if name and not name:match("^%(") then
                psc.add({ name = name, tip = "template package" })
            end
        end
    end
end

psc.on({
    { command = { "package", "remove" }, multiple = true },
    { command = { "package", "update" }, multiple = true }
}, add_packages)

psc.on({
    { command = { "tool", "uninstall" } },
    { command = { "tool", "update" } },
    { command = { "tool", "list" } }
}, add_tools)

psc.on({ command = { "tool", "run" } }, add_tool_commands)

psc.on({ command = { "workload", "install" }, multiple = true }, add_workloads_search)

psc.on({
    { command = { "workload", "uninstall" }, multiple = true },
    { command = { "workload", "update" },    multiple = true }
}, add_workloads_installed)

psc.on({
    { command = { "new", "create" } },
    { command = { "new", "list" } }
}, add_templates)

psc.on({ command = { "new", "uninstall" }, multiple = true }, add_template_packages)
