local function add_packages()
    local data = psc.run({ "pdm", "list", "--json" }, { format = "json" })
    if data then
        for _, pkg in ipairs(data) do
            if pkg.name then psc.add({ name = pkg.name, tip = pkg.version or "" }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "pdm", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and not name:match("^[%-]+") then psc.add({ name = name, tip = line }) end
    end
end

local function add_scripts()
    local data = psc.toml("pyproject.toml")
    if not data then return end
    local scripts = data.tool and data.tool.pdm and data.tool.pdm.scripts
    if scripts then
        for k, v in pairs(scripts) do
            -- scripts may be string or {cmd, composite}; normalize
            local tip = psc.join(v.cmd or v.composite or v, "\n")
            psc.add({ name = k, tip = tip })
        end
    end
    -- fallback: pdm run --list
    for _, line in ipairs(psc.run({ "pdm", "run", "--list" }) or {}) do
        local name = line:match("^%s*(%S+)%s+|")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { command = "remove", multiple = true },
    { command = "show" }
}, add_packages)

psc.on({ command = "run" }, add_scripts)
