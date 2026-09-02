local function add_installed()
    local data = psc.run({ "pip", "list", "--format=json" }, { format = "json" })
    if data then
        for _, pkg in ipairs(data) do
            if pkg.name then
                psc.add({ name = pkg.name, tip = pkg.version or "" })
            elseif type(pkg) == "table" and pkg[1] then
                -- fallback array of arrays
                psc.add({ name = pkg[1], tip = pkg[2] or "" })
            end
        end
        return
    end
    -- fallback: pip freeze lines
    for _, line in ipairs(psc.run({ "pip", "freeze" }) or {}) do
        local name = line:match("^([^=]+)==")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_cache_pkgs()
    for _, line in ipairs(psc.run({ "pip", "cache", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { command = "show", multiple = true },
    { command = "uninstall", multiple = true },
    { command = "download" }
}, add_installed)

psc.on({ command = { "cache", "remove" }, multiple = true }, add_cache_pkgs)
