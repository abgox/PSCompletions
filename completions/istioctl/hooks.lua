local function add_namespaces()
    for _, l in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
        local n = l:match("^namespace/(.*)$") or l
        if n and n ~= "" then psc.add({ name = n }) end
    end
end

local function add_contexts()
    psc.add(psc.items(psc.run({ "kubectl", "config", "get-contexts", "-o", "name" }) or {}))
end

local function add_pods()
    for _, l in ipairs(psc.run({ "kubectl", "get", "pods", "-o", "name" }) or {}) do
        local n = l:match("^[^/]+/(.*)$") or l
        if n and n ~= "" then psc.add({ name = n }) end
    end
end

local function add_istio_revisions()
    for _, l in ipairs(psc.run({ "kubectl", "get", "mutatingwebhookconfigurations", "-o", "name" }) or {}) do
        local n = l:match("^[^/]+/(.*)$") or l
        if n and n ~= "" then psc.add({ name = n }) end
    end
    -- also try istioctl tag list
    for _, l in ipairs(psc.run({ "istioctl", "tag", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^TAG") then
            local tag = l:match("^(%S+)")
            if tag then psc.add({ name = tag }) end
        end
    end
end

psc.on({
    { command = "analyze" },
    { option = "--namespace" }
}, add_namespaces)

psc.on({
    { command = "install" },
    { command = "manifest" },
    { option = "--revision" },
}, add_istio_revisions)

psc.on({ option = "--context" }, add_contexts)

psc.on({
    { command = { "proxy-config", "all" } },
    { command = { "proxy-config", "bootstrap" } },
    { command = { "proxy-config", "clusters" } },
    { command = { "proxy-config", "endpoints" } },
    { command = { "proxy-config", "listeners" } },
    { command = { "proxy-config", "routes" } },
    { command = { "proxy-config", "secrets" } },
    { command = { "proxy-config", "ecds" } },
    { command = { "proxy-config", "log" } },
    { command = "proxy-status" },
    { command = { "experimental", "describe", "pod" } },
    { command = { "experimental", "envoy-stats" } },
    { command = { "experimental", "metrics" } },
    { command = { "experimental", "proxy-status" } }
}, add_pods)
