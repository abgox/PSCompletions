local function add_clusters()
    psc.add(psc.items(psc.run({ "kind", "get", "clusters" }) or {}))
end

local function add_nodes()
    -- if --name value typed, scope to that cluster
    for i, t in ipairs(psc.tokens) do
        if psc.eq(t.name, "--name") and psc.tokens[i + 1] and psc.tokens[i + 1].type == "value" then
            local cn = psc.tokens[i + 1].name
            local lines = psc.run({ "kind", "get", "nodes", "--name", cn }) or {}
            if #lines > 0 then
                psc.add(psc.items(lines))
                return
            end
        end
    end
    -- try all clusters nodes (unscoped)
    local lines = psc.run({ "kind", "get", "nodes" }) or {}
    if #lines > 0 then
        psc.add(psc.items(lines))
        return
    end
    -- fallback: per-cluster batch
    local clusters = psc.run({ "kind", "get", "clusters" }) or {}
    if #clusters > 0 then
        local cmds = {}
        for _, c in ipairs(clusters) do
            table.insert(cmds, { "kind", "get", "nodes", "--name", c })
        end
        local results = psc.run_batch(cmds) or {}
        for _, lst in ipairs(results) do
            psc.add(psc.items(lst or {}))
        end
    end
end

psc.on({
    { command = { "create", "cluster" } },
    { command = { "delete", "cluster" } },
    { command = { "delete", "clusters" },   multiple = true },
    { command = { "get", "clusters" } },
    { command = { "get", "kubeconfig" } },
    { command = { "export", "kubeconfig" } },
    { command = { "export", "logs" } },
    { command = { "load", "docker-image" }, multiple = true },
    { command = { "load", "image-archive" } },
    { option = "--name" }
}, add_clusters)

psc.on({
    { command = { "get", "nodes" } },
    { command = { "load", "docker-image" } },
    { command = { "load", "image-archive" } },
    { option = "--nodes" }
}, add_nodes)
