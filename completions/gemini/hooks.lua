local function add_models()
    for _, m in ipairs({ "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash", "gemma-3" }) do
        psc.add({ name = m, tip = "model" })
    end
end

local function add_extensions()
    local lines = psc.run({ "gemini", "extensions", "list" })
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_]+)")
            if n and n ~= "Extensions" then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
    -- config file fallback
    local cfg = psc.json(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".gemini", "settings.json"))
    if cfg and cfg.extensions then
        for name, _ in pairs(cfg.extensions) do psc.add({ name = name, tip = "extension" }) end
    end
end

local function add_mcp_servers()
    local lines = psc.run({ "gemini", "mcp", "list" })
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_]+)")
            if n then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
    local cfg = psc.json(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".gemini", "settings.json"))
    if cfg and cfg.mcpServers then
        for name, _ in pairs(cfg.mcpServers) do psc.add({ name = name, tip = "mcp server" }) end
    end
end

local function add_skills()
    local lines = psc.run({ "gemini", "skills", "list" })
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_]+)")
            if n then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
end

psc.on({ option = "--model" }, add_models)

psc.on({ command = { "extensions", "" } }, add_extensions)

psc.on({ command = { "mcp", "" } }, add_mcp_servers)

psc.on({ command = { "skills", "" } }, add_skills)
