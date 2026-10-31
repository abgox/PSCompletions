local function add_links(prefix)
    for _, line in ipairs(psc.run({ "networkctl", "list", "--no-legend", "--no-pager" }) or {}) do
        local name = line:match("^%s*%d+%s+(%S+)")
        if name then
            psc.add({ name = prefix .. name })
        end
    end
end

local function add_devices()
    add_links("")
end

-- `edit`/`cat` address a device through the `@` prefix (networkctl(1)).
local function add_config_devices()
    add_links("@")
end

psc.on({
    { command = "list", multiple = true },
    { command = "status", multiple = true },
    { command = "lldp", multiple = true },
    { command = "delete", multiple = true },
    { command = "up", multiple = true },
    { command = "down", multiple = true },
    { command = "renew", multiple = true },
    { command = "forcerenew", multiple = true },
    { command = "reconfigure", multiple = true },
}, add_devices)

psc.on({
    { command = "edit", multiple = true },
    { command = "cat", multiple = true },
}, add_config_devices)
