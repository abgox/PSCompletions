local function add_tools()
    local data = psc.run({ "mise", "ls", "--json" }, { format = "json" })
    if data then
        -- mise ls --json is a map of tool -> versions
        for tool, vers in pairs(data) do
            if type(vers) == "table" then
                for _, v in ipairs(vers) do
                    local ver = type(v) == "table" and (v.version or v) or tostring(v)
                    psc.add({ name = tool .. "@" .. ver, tip = tool })
                end
                psc.add({ name = tool, tip = "tool" })
            else
                psc.add({ name = tool, tip = tostring(vers) })
            end
        end
        return
    end
    for _, line in ipairs(psc.run({ "mise", "ls" }) or {}) do
        local tool = line:match("^(%S+)")
        if tool and not tool:match("^mise") then psc.add({ name = tool, tip = line }) end
    end
end

local function add_tasks()
    local data = psc.run({ "mise", "tasks", "ls", "--json" }, { format = "json" })
    if data then
        for _, t in ipairs(data) do
            local name = t.name or t.task or tostring(t)
            if name and name ~= "" then psc.add({ name = name, tip = t.description or t.source or "" }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "mise", "tasks", "ls" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_plugins()
    for _, line in ipairs(psc.run({ "mise", "plugins", "ls" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { command = "use" },
    { command = "install" },
    { command = "uninstall" },
    { command = "upgrade" },
    { command = "where" },
    { command = "which" }
}, add_tools)

psc.on({
    { command = "run" },
    { command = { "tasks", "run" } }
}, add_tasks)

psc.on({
    { command = { "plugins", "update" } },
    { command = { "plugins", "uninstall" } }
}, add_plugins)
