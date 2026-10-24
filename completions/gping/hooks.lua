local function add_interfaces()
    if psc.platform == "linux" then
        -- The kernel exposes interface names as directory entries.
        for _, entry in ipairs(psc.ls("/sys/class/net") or {}) do
            psc.add({ name = entry.name })
        end
    elseif psc.platform == "macos" then
        for _, line in ipairs(psc.run({ "ifconfig", "-l" }) or {}) do
            for name in line:gmatch("%S+") do
                psc.add({ name = name })
            end
        end
    end
end

-- Windows has no --interface option, so there is no branch for it.
psc.on({ option = "--interface" }, add_interfaces)
