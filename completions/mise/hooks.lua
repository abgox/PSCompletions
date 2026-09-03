local function add_pure_tools()
    local data = psc.run({ "mise", "ls", "--json" }, { format = "json" })
    if not data then return end
    for tool, vers in pairs(data) do
        if type(vers) == "table" then
            psc.add({ name = tool, tip = "tool" })
        end
    end
end

local function add_tools()
    local data = psc.run({ "mise", "ls", "--json" }, { format = "json" })
    if not data then return end
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
end

local function add_tasks()
    local data = psc.run({ "mise", "tasks", "ls", "--json" }, { format = "json" })
    if not data then return end
    for _, t in ipairs(data) do
        local name = t.name or t.task or tostring(t)
        if name and name ~= "" then psc.add({ name = name, tip = t.description or t.source or "" }) end
    end
end

local function add_plugins()
    for _, line in ipairs(psc.run({ "mise", "plugins", "ls" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { command = "list" }
}, add_pure_tools)

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
