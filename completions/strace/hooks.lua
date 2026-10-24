local function add_pid()
    for _, line in ipairs(psc.run({ "ps", "-eo", "pid=,comm=" }) or {}) do
        local pid, comm = line:match("^%s*(%d+)%s+(.*)$")
        if pid then
            psc.add({ name = pid, tip = comm ~= "" and comm or nil })
        end
    end
end

local function add_user()
    local passwd = psc.read("/etc/passwd")
    if not passwd then
        return
    end
    for _, line in ipairs(psc.split(passwd, "\n")) do
        local name, uid, gid = line:match("^([^:]+):[^:]*:(%d+):(%d+):")
        if name and name ~= "+" and name ~= "-" then
            psc.add({ name = name, tip = uid .. ":" .. gid })
        end
    end
end

local function add_env()
    -- Values are omitted so secrets in the environment never reach the menu.
    for _, line in ipairs(psc.run({ "env" }) or {}) do
        local name = line:match("^([^=]+)=")
        if name then
            psc.add({ name = name })
        end
    end
end

local function add_syscall_set()
    -- The set lives once on --trace; mounting avoids three drifting copies.
    psc.add(psc.mount_items({ "option", "--trace", "next" }))
end

psc.on({ option = "--attach", multiple = true }, add_pid)

psc.on({ option = "--user" }, add_user)

psc.on({ option = "--env" }, add_env)

psc.on({
    { option = "--abbrev" },
    { option = "--verbose" },
    { option = "--raw" }
}, add_syscall_set)
