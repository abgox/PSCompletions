local function add_cache_targets()
    psc.add(psc.items(psc.run({ "hf", "cache", "list", "-q" }) or {}))
end

local function add_cache_models()
    -- verify takes a bare repo id (others need --repo-type, which a
    -- positional producer cannot set), so only model/ entries qualify
    for _, line in ipairs(psc.run({ "hf", "cache", "list", "-q" }) or {}) do
        local id = line:match("^model/(.+)$")
        if id then
            psc.add({ name = id })
        end
    end
end

local function add_models()
    psc.add(psc.items(psc.run({ "hf", "models", "list", "-q" }) or {}))
end

local function add_datasets()
    psc.add(psc.items(psc.run({ "hf", "datasets", "list", "-q" }) or {}))
end

local function add_spaces()
    psc.add(psc.items(psc.run({ "hf", "spaces", "list", "-q" }) or {}))
end

local function add_papers()
    psc.add(psc.items(psc.run({ "hf", "papers", "list", "-q" }) or {}))
end

local function add_collections()
    psc.add(psc.items(psc.run({ "hf", "collections", "list", "-q" }) or {}))
end

local function add_skills()
    psc.add(psc.items(psc.run({ "hf", "skills", "list", "-q" }) or {}))
end

local function add_jobs_flavors()
    psc.add(psc.items(psc.run({ "hf", "jobs", "hardware", "-q" }) or {}))
end

local function add_spaces_hardware()
    psc.add(psc.items(psc.run({ "hf", "spaces", "hardware", "-q" }) or {}))
end

psc.on({ command = { "cache", "rm" }, multiple = true }, add_cache_targets)

psc.on({ command = { "cache", "verify" } }, add_cache_models)

psc.on({
    { command = { "models", "card" } },
    { command = { "models", "info" } },
    { command = "download" },
}, add_models)

psc.on({
    { command = { "datasets", "card" } },
    { command = { "datasets", "info" } },
    { command = { "datasets", "leaderboard" } },
    { command = { "datasets", "parquet" } },
    { command = "download" },
}, add_datasets)

psc.on({
    { command = { "spaces", "card" } },
    { command = { "spaces", "dev-mode" } },
    { command = { "spaces", "info" } },
    { command = { "spaces", "logs" } },
    { command = { "spaces", "pause" } },
    { command = { "spaces", "restart" } },
    { command = { "spaces", "settings" } },
    { command = { "spaces", "ssh" } },
    { command = { "spaces", "wait" } },
    { command = { "spaces", "hot-reload" } },
    { command = { "spaces", "secrets", "add" } },
    { command = { "spaces", "variables", "add" } },
    { command = { "spaces", "volumes", "delete" } },
    { command = { "spaces", "volumes", "set" } },
    { command = "download" },
}, add_spaces)

psc.on({
    { command = { "papers", "info" } },
    { command = { "papers", "read" } },
}, add_papers)

psc.on({
    { command = { "collections", "info" } },
    { command = { "collections", "delete" } },
    { command = { "collections", "update" } },
    { command = { "collections", "add-item" } },
    { command = { "collections", "delete-item" } },
    { command = { "collections", "update-item" } },
}, add_collections)

psc.on({
    { command = { "skills", "add" } },
    { command = { "skills", "update" } },
}, add_skills)

psc.on({
    { command = { "jobs", "run" }, option = "--flavor" },
    { command = { "jobs", "scheduled", "run" }, option = "--flavor" },
    { command = { "jobs", "scheduled", "uv", "run" }, option = "--flavor" },
    { command = { "jobs", "uv", "run" }, option = "--flavor" },
    { command = { "sandbox", "create" }, option = "--flavor" },
    { command = { "sandbox", "pool", "create" }, option = "--flavor" },
}, add_jobs_flavors)

psc.on({
    { command = { "repos", "create" }, option = "--flavor" },
    { command = { "repos", "duplicate" }, option = "--flavor" },
    { command = { "spaces", "settings" }, option = "--hardware" },
}, add_spaces_hardware)
