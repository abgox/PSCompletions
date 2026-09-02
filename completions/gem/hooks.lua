local function add_gems()
    local lines = psc.run({ "gem", "list", "--no-versions" }) or {}
    for _, line in ipairs(lines) do
        -- header "*** LOCAL GEMS ***" should be skipped
        if line:match("^%*%*%*") then
            -- skip
        else
            local name = psc.trim(line)
            -- gem list may output space-separated names in one line
            for n in name:gmatch("(%S+)") do
                psc.add({ name = n, tip = "gem" })
            end
        end
    end
end

local function add_gems_with_versions()
    for _, line in ipairs(psc.run({ "gem", "list" }) or {}) do
        if line:match("^%*%*%*") then
            -- skip header
        else
            local name = line:match("^(%S+)")
            if name then
                psc.add({ name = name, tip = line })
            end
        end
    end
end

psc.on({
    { command = "check",      multiple = true },
    { command = "cleanup",    multiple = true },
    { command = "contents",   multiple = true },
    { command = "dependency", multiple = true },
    { command = "fetch",      multiple = true },
    { command = "info",       multiple = true },
    { command = "install",    multiple = true },
    { command = "list",       multiple = true },
    { command = "open" },
    { command = "outdated",   multiple = true },
    { command = "pristine",   multiple = true },
    { command = "rdoc",       multiple = true },
    { command = "search",     multiple = true },
    { command = "stale",      multiple = true },
    { command = "uninstall",  multiple = true },
    { command = "update",     multiple = true },
    { command = "which",      multiple = true },
    { command = "yank" },
    { command = "lock",       multiple = true },
    { command = "mirror" },
    { option = "--gem" }
}, add_gems)

psc.on({
    { command = "contents" },
    { command = "dependency" },
    { command = "info" }
}, add_gems_with_versions)
