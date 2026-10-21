local function kubeconfig_path()
    local kc = psc.env("KUBECONFIG")
    if kc then
        return kc:match("^[^;]+")
    end
    local home = psc.env("USERPROFILE") or psc.env("HOME")
    if home then
        return psc.path(home, ".kube", "config")
    end
end

local function load_kubeconfig()
    local path = kubeconfig_path()
    if path and psc.exist(path) then
        return psc.yaml(path)
    end
end

local function add_contexts()
    local lines = psc.run({ "kubectl", "config", "get-contexts", "-o", "name" }, { timeout = 1000 }) or {}
    if #lines > 0 then
        psc.add(psc.items(lines))
        return
    end
    local cfg = load_kubeconfig()
    if cfg and type(cfg.contexts) == "table" then
        for _, c in ipairs(cfg.contexts) do
            if c and c.name then
                psc.add({ name = c.name })
            end
        end
    end
end

local function add_namespaces()
    local lines = psc.run({ "kubectl", "get", "namespaces", "-o", "name", "--request-timeout=1s" }, { timeout = 1000 }) or {}
    if #lines > 0 then
        for _, l in ipairs(lines) do
            local name = l:match("^[^/]+/(.*)$") or l
            if name ~= "" then
                psc.add({ name = name })
            end
        end
        return
    end
    -- No cluster: the namespaces named by the kubeconfig contexts are still known.
    local cfg = load_kubeconfig()
    local seen = {}
    if cfg and type(cfg.contexts) == "table" then
        for _, c in ipairs(cfg.contexts) do
            local ns = c.context and c.context.namespace
            if ns and ns ~= "" and not seen[ns] then
                seen[ns] = true
                psc.add({ name = ns })
            end
        end
    end
end

local function add_resource(kind)
    local lines = psc.run({ "kubectl", "get", kind, "-o", "name", "--request-timeout=1s" }, { timeout = 1000 }) or {}
    for _, l in ipairs(lines) do
        local name = l:match("^[^/]+/(.*)$") or l
        if name and name ~= "" then
            psc.add({ name = name })
        end
    end
end

-- Resource types are positional values, and api-resources needs a live cluster, so keep a static set.
local function add_resource_types()
    local types = {
        "pods", "deployments", "services", "replicasets", "statefulsets",
        "daemonsets", "jobs", "cronjobs", "configmaps", "secrets",
        "ingresses", "namespaces", "nodes", "persistentvolumeclaims",
        "persistentvolumes", "serviceaccounts", "roles", "clusterroles",
        "rolebindings", "clusterrolebindings", "events", "endpoints"
    }
    psc.add(psc.items(types))
end

local function add_all_resources()
    local kinds = { "pods", "deployments", "services", "configmaps", "secrets", "ingress", "jobs", "cronjobs",
        "statefulsets", "replicasets" }
    local cmds = {}
    for _, k in ipairs(kinds) do
        table.insert(cmds, { "kubectl", "get", k, "-o", "name", "--request-timeout=1s" })
    end
    local results = psc.run_batch(cmds, { timeout = 1000 }) or {}
    for _, lines in ipairs(results) do
        for _, l in ipairs(lines or {}) do
            local name = l:match("^[^/]+/(.*)$") or l
            if name and name ~= "" then
                psc.add({ name = name })
            end
        end
    end
end

psc.on({ command = "get", multiple = true }, function()
    add_resource_types()
    add_all_resources()
end)

psc.on({
    { command = "describe",  multiple = true },
    { command = "delete",    multiple = true },
    { command = "edit",      multiple = true },
    { command = "label",     multiple = true },
    { command = "annotate",  multiple = true },
    { command = "expose",    multiple = true },
    { command = "patch",     multiple = true },
    { command = "replace",   multiple = true },
    { command = "apply",     multiple = true },
    { command = "scale",     multiple = true },
    { command = "autoscale", multiple = true },
    { command = "rollout",   multiple = true },
    { command = "set",       multiple = true }
}, function()
    add_all_resources()
    add_resource_types()
end)

psc.on({
    { command = "logs",         multiple = true },
    { command = "exec",         multiple = true },
    { command = "attach",       multiple = true },
    { command = "cp",           multiple = true },
    { command = "port-forward", multiple = true },
    { command = "debug",        multiple = true },
    { command = { "top", "pod" }, multiple = true }
}, function() add_resource("pods") end)

psc.on({
    { command = "cordon" },
    { command = "drain" },
    { command = "uncordon" },
    { command = "taint" },
    { command = { "top", "node" } },
    { command = "describe", multiple = true }
}, function() add_resource("nodes") end)

psc.on({ option = "--context" }, add_contexts)

psc.on({ option = "--namespace" }, add_namespaces)

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
