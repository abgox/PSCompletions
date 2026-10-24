local function ssh_dir()
    return psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".ssh")
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
                -- a non-default port is recorded as [host]:port, which keyscan takes as a name only
                local host = entry:match("^%[([^%]]+)%]") or entry
                local key = host:lower()
                if host ~= "" and not host:match("[*?]") and not seen[key] then
                    seen[key] = true
                    psc.add({ name = host })
                end
            end
        end
    end
end

psc.on({}, add_known_hosts)
