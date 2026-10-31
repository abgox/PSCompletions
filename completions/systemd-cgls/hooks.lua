local function has(name)
    for _, token in ipairs(psc.tokens) do
        if token.name == name then
            return true
        end
    end
    return false
end

local function add_units()
    local argv = { "systemctl" }
    if has("--user-unit") then
        table.insert(argv, "--user")
    elseif not has("--unit") then
        -- Without --unit/--user-unit the positional is a cgroup path, not a unit.
        return
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

psc.on({ multiple = true }, add_units)
