local function add_interfaces()
    local names = {}
    if psc.platform == "windows" then
        local header = true
        for _, line in ipairs(psc.run({ "netsh", "interface", "show", "interface" }) or {}) do
            if line:match("%S") then
                if header then
                    header = false
                elseif not line:match("^%-+%s*$") then
                    local _, _, _, name = line:match("^%s*(.-)%s%s+(.-)%s%s+(.-)%s%s+(.+)$")
                    if name then
                        names[#names + 1] = name:match("^%s*(.-)%s*$")
                    end
                end
            end
        end
    elseif psc.platform == "macos" then
        for _, line in ipairs(psc.run({ "ifconfig", "-l" }) or {}) do
            for name in line:gmatch("%S+") do
                names[#names + 1] = name
            end
        end
    elseif psc.platform == "linux" then
        for _, line in ipairs(psc.run({ "ip", "-o", "link", "show" }) or {}) do
            local name = line:match("^%d+:%s*([^:@]+)")
            if name then
                names[#names + 1] = name:match("^%s*(.-)%s*$")
            end
        end
    end
    for _, name in ipairs(names) do
        psc.add({ name = name, tip = "interface --- " .. name })
    end
end

psc.on({
    { option = "--interface" },
    { option = "--dns-interface" }
}, add_interfaces)
