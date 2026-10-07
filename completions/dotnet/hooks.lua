local function add_packages()
    -- try dotnet list package
    local lines = psc.run({ "dotnet", "list", "package" }) or {}
    for _, l in ipairs(lines) do
        -- lines like "   > PackageName   1.2.3"
        local name = l:match("^%s*>?%s*([%w%.%-_]+)%s+[%d%.]")
        if not name then
            name = l:match("^%s*([%w%.%-_]+)%s+[%d%.]+")
        end
        if name and name ~= "Project" and name ~= "TopLevelPackage" then
            -- filter header noise
            if not name:match("^%-") then
                psc.add({ name = name, tip = psc.trim(l) })
            end
        end
    end
end

local function add_tools()
    for _, line in ipairs(psc.run({ "dotnet", "tool", "list", "--global" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "Package" and name ~= "--------------------------------" then
            psc.add({ name = name, tip = line })
        end
    end
end

local function add_tool_commands()
    -- local tools: command names live in the last column
    for _, line in ipairs(psc.run({ "dotnet", "tool", "list", "--local" }) or {}) do
        local name = line:match("(%S+)$")
        if name and name ~= "Commands" and not name:match("^%-") then
            psc.add({ name = name, tip = psc.trim(line) })
        end
    end
end

psc.on({
    { command = { "package", "add" } },
    { command = { "package", "remove" },  multiple = true },
    { command = { "package", "list" } },
    { command = { "package", "search" } },
    { command = { "package", "update" } },
    { command = { "package", "download" } }
}, add_packages)

psc.on({
    { command = { "tool", "install" } },
    { command = { "tool", "uninstall" } },
    { command = { "tool", "update" } },
    { command = { "tool", "search" } }
}, add_tools)

psc.on({
    { command = { "tool", "run" } }
}, add_tool_commands)

psc.on({
    { command = { "workload", "install" },   multiple = true },
    { command = { "workload", "uninstall" }, multiple = true },
    { command = { "workload", "update" },    multiple = true }
}, function()
    for _, line in ipairs(psc.run({ "dotnet", "workload", "search" }) or {}) do
        local id = line:match("^(%S+)")
        if id and id ~= "Workload" and id ~= "------" then
            psc.add({ name = id, tip = line })
        end
    end
end)

psc.on({
    { command = { "new", "install" } },
    { command = { "new", "uninstall" } },
    { command = { "new", "list" } },
    { command = { "new", "create" } }
}, function()
    for _, line in ipairs(psc.run({ "dotnet", "new", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "Template" and name ~= "----------------" then
            psc.add({ name = name, tip = line })
        end
    end
end)
