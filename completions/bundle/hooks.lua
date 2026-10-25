local function add_gems()
    psc.add(psc.items(psc.run({ "bundle", "list", "--name-only" }) or {}, function(name)
        return {
            name = name,
            tip = {
                ["en-US"] = "Gem in the bundle",
                ["zh-CN"] = "当前 bundle 中的 gem",
            },
        }
    end))
end

psc.on({
    { command = "show" },
    { command = "info" },
    { command = "open" },
    { command = "binstubs", multiple = true },
    { command = "outdated", multiple = true },
    { command = "pristine", multiple = true },
    { command = "remove",   multiple = true },
    { command = "update",   multiple = true },
    { command = "lock",     option = "--update", multiple = true },
}, add_gems)

-- the key list lives once under `config get`
psc.on({
    { command = "config" },
    { command = { "config", "set" } },
    { command = { "config", "unset" } },
}, function()
    psc.add(psc.mount_items({ "next", "config", "next", "get", "next" }))
end)

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)

psc.on({ command = { "config", "help" } }, function()
    psc.add(psc.mount_items({ "next", "config", "next" }))
end)

psc.on({ command = { "doctor", "help" } }, function()
    psc.add(psc.mount_items({ "next", "doctor", "next" }))
end)

psc.on({ command = { "plugin", "help" } }, function()
    psc.add(psc.mount_items({ "next", "plugin", "next" }))
end)
