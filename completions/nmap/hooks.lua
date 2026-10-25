local function scripts_dir()
    local dirs = {}
    local toks = psc.tokens
    for i, t in ipairs(toks) do
        if t.type == "option" and psc.eq(t.name, "--datadir") then
            local value = toks[i + 1]
            if value and value.type == "value" then
                dirs[#dirs + 1] = psc.path(value.input, "scripts")
            end
        end
    end
    local nmapdir = psc.env("NMAPDIR")
    if nmapdir and nmapdir ~= "" then
        dirs[#dirs + 1] = psc.path(nmapdir, "scripts")
    end
    local home = psc.env("HOME") or psc.env("USERPROFILE") or ""
    if home ~= "" then
        dirs[#dirs + 1] = psc.path(home, ".nmap", "scripts")
    end
    local exe = psc.which("nmap")
    if exe then
        local exedir = exe:match("^(.*)[/\\][^/\\]+$")
        if exedir then
            dirs[#dirs + 1] = psc.path(exedir, "scripts")
            dirs[#dirs + 1] = psc.path(exedir, "..", "share", "nmap", "scripts")
        end
    end
    dirs[#dirs + 1] = "/usr/local/share/nmap/scripts"
    dirs[#dirs + 1] = "/usr/share/nmap/scripts"
    for _, dir in ipairs(dirs) do
        if psc.exist(dir) then
            return dir
        end
    end
end

local function add_script()
    for _, entry in ipairs(psc.ls(scripts_dir()) or {}) do
        local name = not entry.is_dir and entry.name:match("^(.-)%.nse$")
        if name then
            psc.add({ name = name })
        end
    end
end

local function add_iface()
    local in_ifaces = false
    local seen = {}
    for _, line in ipairs(psc.run({ "nmap", "--iflist" }) or {}) do
        if line:find("INTERFACES", 1, true) then
            in_ifaces = true
        elseif in_ifaces then
            local dev = line:match("^(%S+)%s+%(")
            if dev then
                if dev ~= "DEV" and not seen[dev] then
                    seen[dev] = true
                    psc.add({ name = dev })
                end
            elseif line:match("^%s*$") then
                break
            end
        end
    end
end

psc.on({ option = "-e" }, add_iface)

psc.on({
    { option = "--script" },
    { option = "--script-help" }
}, add_script)

psc.on({ option = "--script-help" }, function()
    psc.add(psc.mount_items({ "option", "--script", "next" }))
end)
