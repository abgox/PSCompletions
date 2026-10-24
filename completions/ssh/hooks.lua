local function ssh_dir()
    return psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".ssh")
end

local function add_config_hosts()
    local txt = psc.read(psc.path(ssh_dir(), "config"))
    if not txt then
        return
    end
    local seen = {}
    for line in txt:gmatch("[^\r\n]+") do
        local name, rest = line:match("^%s*([^%s=]+)%s*[%s=]%s*(.+)$")
        if name and name:lower() == "host" then
            rest = rest:gsub("#.*$", "")
            for host in rest:gmatch("%S+") do
                -- a pattern stands for other names; only a literal alias is a destination
                local lower = host:lower()
                if not host:match("[*?!]") and not seen[lower] then
                    seen[lower] = true
                    psc.add({ name = host, tip = "config host" })
                end
            end
        end
    end
end

local function add_known_hosts()
    local txt = psc.read(psc.path(ssh_dir(), "known_hosts"))
    if not txt then
        return
    end
    local seen = {}
    for line in txt:gmatch("[^\r\n]+") do
        local field = line:match("^(%S+)")
        -- a hashed entry (|1|...) cannot be turned back into a hostname
        if field and not field:match("^[#|@]") then
            for entry in field:gmatch("[^,]+") do
                -- a non-default port is recorded as [host]:port, which is not a destination ssh accepts
                local host = entry:match("^%[([^%]]+)%]") or entry
                local key = host:lower()
                if host ~= "" and not host:match("[*?]") and not seen[key] then
                    seen[key] = true
                    psc.add({ name = host, tip = "known host" })
                end
            end
        end
    end
end

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
    psc.add(psc.items(names, function(name)
        return { name = name, tip = "interface" }
    end))
end

local function add_cipher()
    psc.add(psc.items(psc.run({ "ssh", "-Q", "cipher" }) or {}, function(name)
        return { name = name, tip = "cipher" }
    end))
end

local function add_mac()
    psc.add(psc.items(psc.run({ "ssh", "-Q", "mac" }) or {}, function(name)
        return { name = name, tip = "mac" }
    end))
end

psc.on({
    {},
    { option = "-J" }
}, add_config_hosts)

psc.on({
    {},
    { option = "-J" }
}, add_known_hosts)

psc.on({ option = "-B" }, add_interfaces)

psc.on({ option = "-c" }, add_cipher)

psc.on({ option = "-m" }, add_mac)
