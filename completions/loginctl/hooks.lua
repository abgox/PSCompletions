local function add_sessions()
    for _, line in ipairs(psc.run({ "loginctl", "list-sessions", "--no-legend" }) or {}) do
        local id = line:match("^(%S+)")
        if id then
            psc.add({ name = id })
        end
    end
end

local function add_users()
    for _, line in ipairs(psc.run({ "loginctl", "list-users", "--no-legend" }) or {}) do
        local name = line:match("^%S+%s+(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

local function add_seats()
    for _, line in ipairs(psc.run({ "loginctl", "list-seats", "--no-legend" }) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

psc.on({
    { command = "session-status", multiple = true },
    { command = "show-session", multiple = true },
    { command = "activate" },
    { command = "lock-session", multiple = true },
    { command = "unlock-session", multiple = true },
    { command = "terminate-session", multiple = true },
    { command = "kill-session", multiple = true },
}, add_sessions)

psc.on({
    { command = "user-status", multiple = true },
    { command = "show-user", multiple = true },
    { command = "enable-linger", multiple = true },
    { command = "disable-linger", multiple = true },
    { command = "terminate-user", multiple = true },
    { command = "kill-user", multiple = true },
}, add_users)

psc.on({
    { command = "seat-status", multiple = true },
    { command = "show-seat", multiple = true },
    { command = "attach" },
    { command = "terminate-seat", multiple = true },
}, add_seats)
