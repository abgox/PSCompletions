local function add_addresses()
    local seen = {}
    local function offer(address)
        if address and address ~= "" and not seen[address] then
            seen[address] = true
            psc.add({ name = address })
        end
    end

    if psc.platform == "windows" then
        -- PowerShell emits bare addresses, so a localized netsh table cannot misparse.
        local lines = psc.run({
            "powershell.exe", "-NoProfile", "-Command",
            "Get-NetIPAddress | Select-Object -ExpandProperty IPAddress"
        }) or {}
        for _, line in ipairs(lines) do
            offer(line:match("^%s*([%w:%%.]+)%s*$"))
        end
    elseif psc.platform == "macos" then
        for _, line in ipairs(psc.run({ "ifconfig" }) or {}) do
            offer(line:match("^%s*inet6?%s+([%w:%%.]+)"))
        end
    else
        for _, line in ipairs(psc.run({ "ip", "-o", "addr", "show" }) or {}) do
            for address in line:gmatch("inet6?%s+([%x:%.]+)") do
                offer(address)
            end
        end
    end
end

psc.on({ option = "--address" }, add_addresses)
