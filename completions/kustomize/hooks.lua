local function add_dirs_with_kustomization()
    -- suggest dirs containing a kustomization file
    for _, p in ipairs(psc.glob("**/{kustomization.yaml,kustomization.yml,Kustomization}") or {}) do
        local dir = p:match("^(.*)[/\\][^/\\]+$")
        psc.add({ name = dir or "." })
    end
end

local function add_namespaces()
    for _, l in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
        local n = l:match("^namespace/(.*)$") or l
        if n and n ~= "" then psc.add({ name = n }) end
    end
end

psc.on({
    { command = "build" },
    { command = { "cfg", "cat" } },
    { command = { "cfg", "count" } },
    { command = { "cfg", "grep" } },
    { command = { "cfg", "tree" } },
    { command = "localize" },
    { command = { "fn", "run" } }
}, add_dirs_with_kustomization)

psc.on({ command = { "edit", "add", "base" }, multiple = true }, add_dirs_with_kustomization)

psc.on({ option = "--namespace" }, add_namespaces)
