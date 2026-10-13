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

psc.on({
    { command = "dotty", multiple = true },
    { command = "madison", multiple = true },
    { command = "show", multiple = true },
    { command = "showpkg", multiple = true },
    { command = "showsrc", multiple = true },
    { command = "xvcg", multiple = true },
}, add_available)

psc.on({
    { command = "depends", multiple = true },
    { command = "policy", multiple = true },
    { command = "rdepends", multiple = true },
}, add_installed)
