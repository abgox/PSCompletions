local function add_installed()
    local lines = psc.run({ "choco", "list", "--limit-output", "--accept-license" }, { shell = true }) or {}
    for _, line in ipairs(lines) do
        local name = line:match("^([^|]+)|")
        if name then
            local ver = line:match("|(.+)$") or ""
            psc.add({ name = name, tip = ver })
        end
    end
    if #lines == 0 then
        for _, line in ipairs(psc.run({ "choco", "list" }, { shell = true }) or {}) do
            local name = line:match("^(%S+)")
            if name and not name:match("^Chocolatey") then psc.add({ name = name, tip = line }) end
        end
    end
end

local function add_all()
    local lines = psc.run({ "choco", "search", "--limit-output", "--accept-license" }, { shell = true }) or {}
    for _, line in ipairs(lines) do
        local name = line:match("^([^|]+)|")
        if name then psc.add({ name = name, tip = line:match("|(.+)$") or "" }) end
    end
end

psc.on({
    { command = "uninstall", multiple = true },
    { command = "upgrade",   multiple = true },
    { command = "pin" },
    { command = "info" }
}, add_installed)

psc.on({ command = "install", multiple = true }, add_all)
