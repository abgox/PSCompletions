local function add_services()
    -- Prefer docker compose (v2 plugin) then fallback to docker-compose binary
    local lines = psc.run({ "docker", "compose", "config", "--services" }) or {}
    if #lines == 0 then
        lines = psc.run({ "docker-compose", "config", "--services" }) or {}
    end
    psc.add(psc.items(lines))
end

local function add_projects()
    -- Compose project list (docker compose ls)
    local lines = psc.run({ "docker", "compose", "ls", "--format", "{{.Name}}" }) or {}
    if #lines == 0 then
        lines = psc.run({ "docker-compose", "ls", "--format", "{{.Name}}" }) or {}
    end
    psc.add(psc.items(lines))
end

psc.on({
    { command = "attach" },
    { command = "commit" },
    { command = "exec" },
    { command = "export" },
    { command = "port" },
    { command = "run" },
    { command = "cp" },
    { command = "build",   multiple = true },
    { command = "config",  multiple = true },
    { command = "create",  multiple = true },
    { command = "down",    multiple = true },
    { command = "events",  multiple = true },
    { command = "images",  multiple = true },
    { command = "kill",    multiple = true },
    { command = "logs",    multiple = true },
    { command = "pause",   multiple = true },
    { command = "ps",      multiple = true },
    { command = "pull",    multiple = true },
    { command = "push",    multiple = true },
    { command = "restart", multiple = true },
    { command = "rm",      multiple = true },
    { command = "start",   multiple = true },
    { command = "stats",   multiple = true },
    { command = "stop",    multiple = true },
    { command = "top",     multiple = true },
    { command = "unpause", multiple = true },
    { command = "up",      multiple = true },
    { command = "wait",    multiple = true },
    { command = "watch",   multiple = true },
    { command = "volumes", multiple = true },
    { command = "scale",   multiple = true }
}, add_services)

psc.on({ command = "ls" }, add_projects)
