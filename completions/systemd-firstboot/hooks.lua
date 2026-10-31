local function add_timezones()
    for _, zone in ipairs(psc.run({ "timedatectl", "list-timezones" }) or {}) do
        psc.add({ name = zone })
    end
end

-- /etc/shells is the fixed set of login shells; firstboot writes the chosen path as-is.
local function add_shells()
    for _, line in ipairs(psc.split(psc.read("/etc/shells") or "", "\n")) do
        local shell = line:match("^%s*([^#%s]%S*)")
        if shell then
            psc.add({ name = shell })
        end
    end
end

psc.on({ option = "--timezone" }, add_timezones)
psc.on({ option = "--root-shell" }, add_shells)
