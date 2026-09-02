local function add_versions()
    for _, line in ipairs(psc.run({ "nvm", "list" }, { shell = true }) or {}) do
        -- nvm list outputs lines like " * 18.19.0 (Currently using ...)" or "  20.11.0"
        local v = line:match("(%d+%.%d+%.%d+)")
        if v then psc.add({ name = v, tip = psc.trim(line) }) end
    end
end

local function add_remote_versions()
    for _, line in ipairs(psc.run({ "nvm", "list", "available" }, { shell = true }) or {}) do
        local v = line:match("(%d+%.%d+%.%d+)")
        if v then psc.add({ name = v, tip = psc.trim(line) }) end
    end
end

psc.on({
    { command = "use" },
    { command = "uninstall" }
}, add_versions)

psc.on({ command = "install" }, add_remote_versions)
