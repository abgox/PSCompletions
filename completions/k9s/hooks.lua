local function add_contexts()
    local lines = psc.run({ "kubectl", "config", "get-contexts", "-o", "name" }) or {}
    if #lines > 0 then
        psc.add(psc.items(lines))
        return
    end
    local kc = psc.env("KUBECONFIG")
    local path
    if kc then
        path = kc:match("^[^;]+")
    else
        local home = psc.env("USERPROFILE") or psc.env("HOME")
        if home then path = psc.path(home, ".kube", "config") end
    end
    if path and psc.exist(path) then
        local cfg = psc.yaml(path)
        if cfg and type(cfg.contexts) == "table" then
            for _, c in ipairs(cfg.contexts) do
                if c and c.name then psc.add({ name = c.name }) end
            end
        end
    end
end

local function add_namespaces()
    for _, l in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
        local n = l:match("^namespace/(.*)$") or l
        if n and n ~= "" then psc.add({ name = n }) end
    end
end

local function add_clusters()
    psc.add(psc.items(psc.run({ "kubectl", "config", "get-clusters" }) or {}))
end

psc.on({ option = "--context" }, add_contexts)

psc.on({ option = "--cluster" }, add_clusters)

psc.on({ option = "--namespace" }, add_namespaces)

psc.on({ option = "--kubeconfig" }, function()
    local home = psc.env("USERPROFILE") or psc.env("HOME")
    if home then
        local dir = psc.path(home, ".kube")
        for _, e in ipairs(psc.ls(dir) or {}) do
            if not e.is_dir then psc.add({ name = e.path }) end
        end
        psc.add({ name = psc.path(home, ".kube", "config") })
    end
end)

psc.on({ option = "--command" }, function()
    psc.add(psc.items({ "pods", "deployments", "services", "configmaps", "secrets", "ingresses", "nodes" }))
end)
