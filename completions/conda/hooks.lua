local function add_envs()
    local data = psc.run({ "conda", "env", "list", "--json" }, { format = "json" })
    if data and data.envs then
        for _, p in ipairs(data.envs) do
            local name = p:match("([^/\\]+)$")
            if name then psc.add({ name = name, tip = p }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "conda", "env", "list" }) or {}) do
        if not line:match("^#") and not line:match("^%s*$") then
            -- env list lines are "<name>  *?  <path>"
            local n = line:match("^(%S+)%s+[* ]")
            if n then psc.add({ name = n, tip = line }) end
        end
    end
end

local function add_packages()
    local data = psc.run({ "conda", "list", "--json" }, { format = "json" })
    if data then
        for _, pkg in ipairs(data) do
            if pkg.name then psc.add({ name = pkg.name, tip = pkg.version }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "conda", "list" }) or {}) do
        if not line:match("^#") then
            local name = line:match("^(%S+)")
            if name then psc.add({ name = name, tip = line }) end
        end
    end
end

psc.on({
    { option = "--name" },
    { command = "activate" },
    { command = { "env", "remove" } },
    { command = { "env", "export" } },
    { command = "run" }
}, add_envs)

psc.on({
    { command = "list" },
    { command = "uninstall", multiple = true },
    { command = "upgrade",   multiple = true }
}, add_packages)
