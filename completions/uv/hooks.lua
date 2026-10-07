local function add_packages()
    local data = psc.run({ "uv", "pip", "list", "--format", "json" }, { format = "json" })
    if type(data) ~= "table" then return end
    for _, pkg in ipairs(data) do
        if pkg.name then
            if pkg.version then
                psc.add({ name = pkg.name, tip = pkg.version })
            else
                psc.add({ name = pkg.name })
            end
        end
    end
end

local function add_pythons()
    for _, line in ipairs(psc.run({ "uv", "python", "list" }) or {}) do
        local v = line:match("^(cpython%S*)") or line:match("^(%d+%.%d+%.%d+)")
        if v then psc.add({ name = v, tip = line }) end
    end
end

psc.on({
    { option = "--with" },
    { command = { "pip", "uninstall" }, multiple = true },
    { command = { "pip", "show" } },
    { command = "remove",               multiple = true }
}, add_packages)

psc.on({
    { option = "--python" },
    { command = { "python", "install" }, multiple = true },
    { command = { "python", "upgrade" }, multiple = true },
    { command = { "python", "pin" } }
}, add_pythons)
