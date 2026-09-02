local function add_models()
    for _, m in ipairs({ "gpt-4o", "gpt-4o-mini", "o1", "o1-mini", "claude-sonnet-4", "claude-opus-4" }) do
        psc.add({ name = m, tip = "model" })
    end
end

local function add_mcp_servers()
    local lines = psc.run({ "copilot", "mcp", "list" })
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_]+)")
            if n and n ~= "MCP" then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
    local cfg = psc.json(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".copilot", "config.json"))
    if cfg and cfg.mcpServers then
        for name, _ in pairs(cfg.mcpServers) do psc.add({ name = name, tip = "mcp server" }) end
    end
end

local function add_plugins()
    local lines = psc.run({ "copilot", "plugins", "list" })
    if not lines then lines = psc.run({ "copilot", "plugin", "list" }) end
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_/]+)")
            if n then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
end

local function add_skills()
    local lines = psc.run({ "copilot", "skill", "list" })
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_]+)")
            if n then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
end

psc.on({ option = "--model" }, add_models)

psc.on({ command = { "mcp", "" } }, add_mcp_servers)

psc.on({
    { command = "plugins" },
    { command = { "plugin", "" } }
}, add_plugins)

psc.on({ command = { "skill", "" } }, add_skills)
