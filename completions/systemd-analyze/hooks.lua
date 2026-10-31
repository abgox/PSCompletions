local function has(name)
    for _, token in ipairs(psc.tokens) do
        if token.name == name then
            return true
        end
    end
    return false
end

local function add_units(services_only)
    -- security --offline= takes unit files, not unit names.
    if has("--offline") then
        return
    end
    local argv = { "systemctl" }
    if has("--user") then
        table.insert(argv, "--user")
    end
    table.insert(argv, "list-units")
    table.insert(argv, "--all")
    table.insert(argv, "--no-legend")
    table.insert(argv, "--plain")
    for _, line in ipairs(psc.run(argv) or {}) do
        local name = line:match("^(%S+)")
        if name and (not services_only or name:match("%.service$")) then
            psc.add({ name = name })
        end
    end
end

local function add_all_units()
    add_units(false)
end

-- security and fdstore reject non-service units.
local function add_service_units()
    add_units(true)
end

local function add_names(argv, pattern)
    for _, line in ipairs(psc.run(argv) or {}) do
        local name = line:match(pattern)
        if name and name ~= "NAME" then
            psc.add({ name = name })
        end
    end
end

local function add_capabilities()
    add_names({ "systemd-analyze", "capability" }, "^(%S+)")
end

local function add_architectures()
    add_names({ "systemd-analyze", "architectures" }, "^(%S+)")
end

local function add_exit_statuses()
    add_names({ "systemd-analyze", "exit-status" }, "^(%S+)")
end

local function add_filesystem_sets()
    add_names({ "systemd-analyze", "filesystems" }, "^(@%S+)")
end

local function add_filter_sets()
    add_names({ "systemd-analyze", "syscall-filter" }, "^(@%S+)")
end

local function add_bus_services()
    for _, line in ipairs(psc.run({ "busctl", "list", "--no-legend", "--no-pager" }) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

psc.on({
    { command = "critical-chain", multiple = true },
    { command = "dot", multiple = true },
    { command = "dump", multiple = true },
}, add_all_units)

psc.on({
    { command = "security", multiple = true },
    { command = "fdstore", multiple = true },
}, add_service_units)

psc.on({ option = "--unit" }, add_all_units)

psc.on({ command = "capability", multiple = true }, add_capabilities)
psc.on({ command = "architectures", multiple = true }, add_architectures)
psc.on({ command = "exit-status", multiple = true }, add_exit_statuses)
psc.on({ command = "filesystems", multiple = true }, add_filesystem_sets)
psc.on({ command = "syscall-filter", multiple = true }, add_filter_sets)
psc.on({ command = "malloc", multiple = true }, add_bus_services)
