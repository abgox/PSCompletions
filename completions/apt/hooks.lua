local function add_available()
    psc.add(psc.items(psc.run({ "apt-cache", "pkgnames" }) or {}))
end

local function add_installed()
    local lines = psc.run({ "dpkg-query", "-W", "-f=${Package} ${Version}\n" }) or {}
    for _, line in ipairs(lines) do
        local name, ver = line:match("^(%S+)%s*(%S*)$")
        if name then
            if ver == "" then ver = nil end
            psc.add({ name = name, tip = ver })
        end
    end
end

local function add_upgradable()
    for _, line in ipairs(psc.run({ "apt", "list", "--upgradable" }) or {}) do
        -- Lines look like "bash/noble-updates 5.1-6ubuntu1.1 amd64 [upgradable from: ...]".
        local name = line:match("^([^/]+)/")
        if name then
            local from = line:match("%[upgradable from:%s*([^%]]+)%]")
            local tip = from and ("upgradable from " .. from) or line
            psc.add({ name = name, tip = tip })
        end
    end
end

psc.on({
    { command = "build-dep", multiple = true },
    { command = "download",  multiple = true },
    { command = "install",   multiple = true },
    { command = "show",      multiple = true },
    { command = "showsrc",   multiple = true },
    { command = "source",    multiple = true },
}, add_available)

psc.on({
    { command = "changelog", multiple = true },
    { command = "depends",   multiple = true },
    { command = "policy",    multiple = true },
    { command = "purge",     multiple = true },
    { command = "rdepends",  multiple = true },
    { command = "reinstall", multiple = true },
    { command = "remove",    multiple = true },
}, add_installed)

psc.on({ command = "upgrade", multiple = true }, add_upgradable)
