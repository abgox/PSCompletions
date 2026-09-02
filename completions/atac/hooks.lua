local function get_dir()
    for i, t in ipairs(psc.tokens) do
        if psc.eq(t.name, "--directory") and psc.tokens[i + 1] and psc.tokens[i + 1].type == "value" then
            return psc.tokens[i + 1].name
        end
    end
    return psc.env("ATAC_MAIN_DIR") or psc.cwd
end

local function add_collections()
    local dir = get_dir()
    for _, p in ipairs(psc.glob(psc.path(dir, "*.json")) or {}) do
        local name = p:match("([^/\\]+)%.json$")
        if name then
            psc.add({ name = name, tip = p })
        end
    end
    for _, p in ipairs(psc.glob(psc.path(dir, "*.yaml")) or {}) do
        local name = p:match("([^/\\]+)%.yaml$")
        if name then
            psc.add({ name = name, tip = p })
        end
    end
    for _, p in ipairs(psc.glob(psc.path(dir, "*.yml")) or {}) do
        local name = p:match("([^/\\]+)%.yml$")
        if name then
            psc.add({ name = name, tip = p })
        end
    end
    for _, line in ipairs(psc.run({ "atac", "collection", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "collection" then
            psc.add({ name = name, tip = line })
        end
    end
end

local function add_requests()
    -- requests are COLLECTION/REQUEST; offer collections then requests
    add_collections()
    for _, line in ipairs(psc.run({ "atac", "collection", "list", "--request-names" }) or {}) do
        -- format may be "collection / request"
        for req in line:gmatch("%S+") do
            if req:match("/") then psc.add({ name = req, tip = line }) end
        end
    end
end

local function add_envs()
    -- env files are .env.<name>
    for _, p in ipairs(psc.glob(".env.*") or {}) do
        local name = p:match("%.env%.(.+)$")
        if name then psc.add({ name = name, tip = p }) end
    end
    for _, line in ipairs(psc.run({ "atac", "env", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { command = { "collection", "delete" } },
    { command = { "collection", "info" } },
    { command = { "collection", "rename" } },
    { command = { "collection", "send" } },
    { command = { "request", "new" } },
    { command = { "request", "delete" } },
    { command = { "request", "info" } },
    { command = { "request", "send" } }
}, add_collections)

psc.on({
    { command = { "request", "auth" } },
    { command = { "request", "body" } },
    { command = { "request", "header" } },
    { command = { "request", "params" } },
    { command = { "request", "method" } },
    { command = { "request", "url" } },
    { command = { "request", "scripts" } },
    { command = { "request", "settings" } },
    { command = { "request", "export" } },
    { command = { "request", "rename" } }
}, add_requests)

psc.on({
    { command = { "env", "info" } },
    { command = { "env", "key" } },
    { option = "--env" }
}, add_envs)
