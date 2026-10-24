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
        -- a hashed entry (|1|...) cannot be turned back into a name
        if field and not field:match("^[#|@]") then
            for entry in field:gmatch("[^,]+") do
                -- [host]:port is the port form -F and -R accept, so keep it as recorded
                local key = entry:lower()
                if entry ~= "" and not entry:match("[*?]") and not seen[key] then
                    seen[key] = true
                    psc.add({ name = entry, tip = "known_host" })
                end
            end
        end
    end
end

psc.on({
    { option = "-F" },
    { option = "-R" }
}, add_known_hosts)
