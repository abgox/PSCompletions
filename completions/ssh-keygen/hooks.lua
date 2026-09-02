local function add_key_files()
    for _, p in ipairs(psc.glob("*.pub") or {}) do
        psc.add({ name = p, tip = "public key" })
    end
    for _, e in ipairs(psc.ls(psc.env("HOME") or psc.env("USERPROFILE") or psc.cwd) or {}) do
        if e.name:match("id_") then psc.add({ name = e.path, tip = e.name }) end
    end
    for _, p in ipairs(psc.glob(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".ssh", "*")) or {}) do
        psc.add({ name = p, tip = "ssh key" })
    end
end

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
    { option = "-f" },
    { option = "-s" }
}, add_key_files)

psc.on({
    { option = "-F" },
    { option = "-R" },
    { option = "-r" }
}, add_known_hosts)
