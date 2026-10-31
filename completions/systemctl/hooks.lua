local function add_units()
    local argv = { "systemctl" }
    for _, token in ipairs(psc.tokens) do
        if token.name == "--user" or token.input == "--user" then
            table.insert(argv, "--user")
            break
        end
    end
    table.insert(argv, "list-units")
    table.insert(argv, "--all")
    table.insert(argv, "--no-legend")
    table.insert(argv, "--plain")
    for _, line in ipairs(psc.run(argv) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

psc.on({
    { command = "list-units", multiple = true },
    { command = "list-automounts", multiple = true },
    { command = "list-paths", multiple = true },
    { command = "list-sockets", multiple = true },
    { command = "list-timers", multiple = true },
    { command = "is-active", multiple = true },
    { command = "is-failed", multiple = true },
    { command = "status", multiple = true },
    { command = "show", multiple = true },
    { command = "cat", multiple = true },
    { command = "help", multiple = true },
    { command = "list-dependencies", multiple = true },
    { command = "start", multiple = true },
    { command = "stop", multiple = true },
    { command = "reload", multiple = true },
    { command = "restart", multiple = true },
    { command = "try-restart", multiple = true },
    { command = "reload-or-restart", multiple = true },
    { command = "try-reload-or-restart", multiple = true },
    { command = "kill", multiple = true },
    { command = "clean", multiple = true },
    { command = "freeze", multiple = true },
    { command = "thaw", multiple = true },
    { command = "reset-failed", multiple = true },
    { command = "list-unit-files", multiple = true },
    { command = "enable", multiple = true },
    { command = "disable", multiple = true },
    { command = "reenable", multiple = true },
    { command = "preset", multiple = true },
    { command = "is-enabled", multiple = true },
    { command = "mask", multiple = true },
    { command = "unmask", multiple = true },
    { command = "revert", multiple = true },
    { command = "edit", multiple = true },
    -- The second positional is not a unit, so these fire once only.
    { command = "isolate" },
    { command = "set-property" },
    { command = "bind" },
    { command = "mount-image" },
    { command = "service-log-level" },
    { command = "service-log-target" },
    { command = "add-wants" },
    { command = "add-requires" },
    { command = "set-default" },
}, add_units)
