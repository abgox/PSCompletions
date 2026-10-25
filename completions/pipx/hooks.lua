local function add_environments()
    local data = psc.run({ "pipx", "list", "--json" }, { format = "json" })
    if not data or type(data.venvs) ~= "table" then
        return
    end
    local names = {}
    for name in pairs(data.venvs) do
        if type(name) == "string" and name ~= "" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        psc.add({
            name = name,
            tip = { ["en-US"] = "pipx environment", ["zh-CN"] = "pipx 环境" },
        })
    end
end

psc.on({
    { command = "uninject" },
    { command = "inject" },
    { command = "expose" },
    { command = "unexpose" },
    { command = "pin" },
    { command = "unpin" },
    { command = "upgrade",       multiple = true },
    { command = "uninstall" },
    { command = "reinstall" },
    { command = "health",        multiple = true },
    { command = "repair",        multiple = true },
    { command = "list",          multiple = true },
    { command = "exec" },
    { command = "runpip" },
    { command = "upgrade-all",   option = "--skip", multiple = true },
    { command = "reinstall-all", option = "--skip", multiple = true },
}, add_environments)

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
