local function add_models()
    local models = { "sonnet", "opus", "haiku", "sonnet[1m]", "opus[1m]" }
    for _, m in ipairs(models) do psc.add({ name = m, tip = "claude model" }) end
    -- try claude config for custom models
    local cfg = psc.json(psc.path(psc.env("APPDATA") or "", "Claude", "settings.json")) or
        psc.json(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".claude", "settings.json"))
    if cfg and cfg.model then psc.add({ name = cfg.model, tip = "configured model" }) end
end

local function add_mcp_servers()
    -- Claude Code stores mcp servers in ~/.claude.json or .claude/settings.json
    local paths = {
        psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".claude.json"),
        psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".claude", "settings.json"),
        ".claude/settings.json",
        "claude.json"
    }
    local maps = psc.json_batch(paths)
    for _, data in pairs(maps) do
        if data and data.mcpServers then
            for name, cfg in pairs(data.mcpServers) do
                local tip = "mcp server"
                if type(cfg) == "table" and cfg.command then tip = cfg.command end
                psc.add({ name = name, tip = tip })
            end
        end
    end
    -- also try via claude mcp list
    local lines = psc.run({ "claude", "mcp", "list" })
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_]+)%s*:")
            if n then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
end

local function add_agents()
    -- agents are markdown files in .claude/agents
    for _, p in ipairs(psc.glob(".claude/agents/*.md") or {}) do
        local n = p:match("([^/\\]+)%.md$")
        if n then psc.add({ name = n, tip = p }) end
    end
    for _, p in ipairs(psc.glob(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".claude", "agents", "*.md")) or {}) do
        local n = p:match("([^/\\]+)%.md$")
        if n then psc.add({ name = n, tip = p }) end
    end
end

psc.on({ option = "--model" }, add_models)

psc.on({
    { option = "--agent" },
    { option = "--agents" }
}, add_agents)

psc.on({
    { command = { "mcp", "get" } },
    { command = { "mcp", "remove" } },
    { command = { "mcp", "login" } },
    { command = { "mcp", "logout" } }
}, add_mcp_servers)
