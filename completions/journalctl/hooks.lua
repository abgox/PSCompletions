local function add_units()
    for _, line in ipairs(psc.run({ "systemctl", "list-units", "--all", "--no-legend", "--plain" }) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

local function add_user_units()
    for _, line in ipairs(psc.run({ "systemctl", "--user", "list-units", "--all", "--no-legend", "--plain" }) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

psc.on({ option = "--unit" }, add_units)

psc.on({ option = "--user-unit" }, add_user_units)
