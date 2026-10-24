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
                if not host:match("[*?!]") and not seen[host:lower()] then
                    seen[host:lower()] = true
                    -- the destination needs the colon even when the remote directory is omitted
                    psc.add({ name = host .. ":", tip = "config host" })
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
                local host, port = entry:match("^%[([^%]]+)%]:(%d+)$")
                host = host or entry
                if host ~= "" and not host:match("[*?]") and not seen[host:lower()] then
                    seen[host:lower()] = true
                    psc.add({
                        name = host .. ":",
                        tip = port and ("known host (port " .. port .. ")") or "known host",
                    })
                end
            end
        end
    end
end

psc.on({}, add_config_hosts)

psc.on({}, add_known_hosts)
