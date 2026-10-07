local function add_known_hosts()
    local kh = psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".ssh", "known_hosts")
    local txt = psc.read(kh)
    if txt then
        for line in txt:gmatch("[^\r\n]+") do
            local host = line:match("^([^%s,]+)")
            if host and not host:match("^#") and not host:match("^|") then
                psc.add({ name = host, tip = "known_host" })
            end
        end
    end
end

psc.on({
    { option = "-F" },
    { option = "-R" },
    { option = "-r" }
}, add_known_hosts)
