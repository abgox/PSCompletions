local function add_timezones()
    for _, zone in ipairs(psc.run({ "timedatectl", "list-timezones" }) or {}) do
        psc.add({ name = zone })
    end
end

psc.on({ command = "set-timezone" }, add_timezones)
