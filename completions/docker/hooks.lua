local function add_all_containers()
    psc.add(psc.items(psc.run({ "docker", "ps", "-a", "--format", "{{.Names}}" }) or {}))
end

local function add_running_containers()
    psc.add(psc.items(psc.run({ "docker", "ps", "--format", "{{.Names}}" }) or {}))
end

local function add_images()
    -- Repository:Tag list; filter empty handled by psc.add no-op for blank names
    local lines = psc.run({ "docker", "images", "--format", "{{.Repository}}:{{.Tag}}" }) or {}
    for _, v in ipairs(lines) do
        if v ~= "<none>:<none>" and v ~= "" then
            psc.add({ name = v })
        end
    end
end

local function add_networks()
    psc.add(psc.items(psc.run({ "docker", "network", "ls", "--format", "{{.Name}}" }) or {}))
end

local function add_volumes()
    psc.add(psc.items(psc.run({ "docker", "volume", "ls", "--format", "{{.Name}}" }) or {}))
end

local function add_contexts()
    psc.add(psc.items(psc.run({ "docker", "context", "ls", "--format", "{{.Name}}" }) or {}))
end

psc.on({
    { command = "attach" },
    { command = "commit" },
    { command = "cp" },
    { command = "diff" },
    { command = "export" },
    { command = "inspect",                  multiple = true },
    { command = "kill",                     multiple = true },
    { command = "logs" },
    { command = "pause",                    multiple = true },
    { command = "port" },
    { command = "rename" },
    { command = "restart",                  multiple = true },
    { command = "rm",                       multiple = true },
    { command = "start",                    multiple = true },
    { command = "stats",                    multiple = true },
    { command = "stop",                     multiple = true },
    { command = "top" },
    { command = "unpause",                  multiple = true },
    { command = "update",                   multiple = true },
    { command = "wait",                     multiple = true },
    { command = { "container", "attach" } },
    { command = { "container", "commit" } },
    { command = { "container", "cp" } },
    { command = { "container", "diff" } },
    { command = { "container", "export" } },
    { command = { "container", "inspect" }, multiple = true },
    { command = { "container", "kill" },    multiple = true },
    { command = { "container", "logs" } },
    { command = { "container", "pause" },   multiple = true },
    { command = { "container", "port" } },
    { command = { "container", "rename" } },
    { command = { "container", "restart" }, multiple = true },
    { command = { "container", "rm" },      multiple = true },
    { command = { "container", "start" },   multiple = true },
    { command = { "container", "stats" },   multiple = true },
    { command = { "container", "stop" },    multiple = true },
    { command = { "container", "top" } },
    { command = { "container", "unpause" }, multiple = true },
    { command = { "container", "update" },  multiple = true },
    { command = { "container", "wait" },    multiple = true }
}, add_all_containers)

psc.on({
    { command = "exec" },
    { command = { "container", "exec" } },
    { command = { "checkpoint", "create" } },
    { command = { "checkpoint", "ls" } },
    { command = { "checkpoint", "rm" } }
}, add_running_containers)

psc.on({
    { command = "history" },
    { command = "create" },
    { command = "run" },
    { command = "rmi",                      multiple = true },
    { command = "tag" },
    { command = "save",                     multiple = true },
    { command = "load" },
    { command = "push" },
    { command = "pull" },
    { command = { "image", "history" } },
    { command = { "image", "inspect" },     multiple = true },
    { command = { "image", "load" } },
    { command = { "image", "pull" } },
    { command = { "image", "push" } },
    { command = { "image", "rm" },          multiple = true },
    { command = { "image", "save" },        multiple = true },
    { command = { "image", "tag" } },
    { command = { "container", "create" } },
    { command = { "container", "run" } },
    { command = "inspect",                  multiple = true },
    { command = { "container", "inspect" }, multiple = true },
    { command = { "image", "inspect" },     multiple = true }
}, add_images)

psc.on({
    { command = { "network", "connect" } },
    { command = { "network", "disconnect" } },
    { command = { "network", "inspect" },   multiple = true },
    { command = { "network", "rm" },        multiple = true }
}, add_networks)

psc.on({
    { command = { "volume", "inspect" }, multiple = true },
    { command = { "volume", "rm" },      multiple = true }
}, add_volumes)

psc.on({
    { command = { "context", "inspect" }, multiple = true },
    { command = { "context", "rm" },      multiple = true },
    { command = { "context", "use" } },
    { command = { "context", "update" } },
    { command = { "context", "export" } },
    { command = { "context", "show" } },
    { option = "--context" }
}, add_contexts)
