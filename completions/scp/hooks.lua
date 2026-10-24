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

local function add_cipher()
    psc.add(psc.items(psc.run({ "ssh", "-Q", "cipher" }) or {}, function(name)
        return { name = name, tip = "cipher" }
    end))
end

psc.on({ option = "-J" }, add_config_hosts)

psc.on({ option = "-J" }, add_known_hosts)

psc.on({ option = "-c" }, add_cipher)
