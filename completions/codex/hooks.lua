local function add_models()
    local models = { "o3", "o4-mini", "gpt-4o", "gpt-4.1", "gpt-5" }
    for _, m in ipairs(models) do psc.add({ name = m, tip = "codex model" }) end
    local cfg = psc.toml(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".codex", "config.toml"))
    if cfg and cfg.model then psc.add({ name = cfg.model, tip = "configured" }) end
end

local function add_mcp_servers()
    local cfg = psc.toml(psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".codex", "config.toml"))
    if cfg and cfg.mcp_servers then
        for name, _ in pairs(cfg.mcp_servers) do
            psc.add({ name = name, tip = "mcp server" })
        end
    end
    -- codex mcp list fallback
    local lines = psc.run({ "codex", "mcp", "list" })
    if lines then
        for _, line in ipairs(lines) do
            local n = line:match("^%s*([%w%-%_]+)")
            if n and n ~= "MCP" then psc.add({ name = n, tip = psc.trim(line) }) end
        end
    end
end

local function add_sessions()
    local dir = psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".codex", "sessions")
    local entries = psc.ls(dir)
    if not entries then return end
    for _, e in ipairs(entries) do
        if not e.is_dir then
            local n = e.name:gsub("%.json$", "")
            psc.add({ name = n, tip = e.path })
        end
    end
end

local function add_plugins()
    local dir = psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".codex", "plugins")
    local entries = psc.ls(dir)
    if not entries then return end
    for _, e in ipairs(entries) do
        psc.add({ name = e.name, tip = e.path })
    end
end

psc.on({ option = "--model" }, add_models)

psc.on({ option = "--config" }, function()
    for _, p in ipairs(psc.glob("**/config.toml") or {}) do
        psc.add({ name = p, tip = p })
    end
end)

psc.on({
    { command = { "mcp", "get" } },
    { command = { "mcp", "remove" } }
}, add_mcp_servers)

psc.on({
    { command = "resume" },
    { command = "fork" },
    { command = "archive" },
    { command = "delete" },
    { command = "unarchive" }
}, add_sessions)

psc.on({ command = { "plugin", "" } }, add_plugins)
