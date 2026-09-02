local function add_resource(kind)
    local lines = psc.run({ "kubectl", "get", kind, "-o", "name" }) or {}
    for _, l in ipairs(lines) do
        local name = l:match("^[^/]+/(.*)$") or l
        if name and name ~= "" then
            psc.add({ name = name })
        end
    end
end

local function add_contexts()
    -- try kubectl first, then fallback to kubeconfig file
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
        if home then
            path = psc.path(home, ".kube", "config")
        end
    end
    if path and psc.exist(path) then
        local cfg = psc.yaml(path)
        if cfg and type(cfg.contexts) == "table" then
            for _, c in ipairs(cfg.contexts) do
                if c and c.name then
                    psc.add({ name = c.name })
                end
            end
        end
    end
end

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
    -- batch common resource types in parallel
    local kinds = { "pods", "deployments", "services", "configmaps", "secrets", "ingress", "jobs", "cronjobs",
        "statefulsets", "replicasets" }
    local cmds = {}
    for _, k in ipairs(kinds) do
        table.insert(cmds, { "kubectl", "get", k, "-o", "name" })
    end
    local results = psc.run_batch(cmds) or {}
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
    { command = "create",    multiple = true },
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
    { command = "debug",        multiple = true }
}, function() add_resource("pods") end)

psc.on({
    { command = "cordon" },
    { command = "drain" },
    { command = "uncordon" },
    { command = "taint" },
    { command = "top" },
    { command = "describe", multiple = true }
}, function() add_resource("nodes") end)

psc.on({ command = "expose", multiple = true }, function()
    add_resource("services")
    add_resource("deployments")
    add_resource("pods")
end)

psc.on({ command = "config" }, add_contexts)
