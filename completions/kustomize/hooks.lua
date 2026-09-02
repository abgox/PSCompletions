local function add_dirs_with_kustomization()
    -- suggest dirs containing kustomization.yaml/yml
    for _, p in ipairs(psc.glob("**/kustomization.yaml") or {}) do
        local dir = p:match("^(.*)[/\\]kustomization%.yaml$")
        if dir then
            psc.add({ name = dir })
        else
            psc.add({ name = "." })
        end
    end
    for _, p in ipairs(psc.glob("**/kustomization.yml") or {}) do
        local dir = p:match("^(.*)[/\\]kustomization%.yml$")
        if dir then psc.add({ name = dir }) end
    end
    for _, p in ipairs(psc.glob("**/Kustomization") or {}) do
        local dir = p:match("^(.*)[/\\]Kustomization$")
        if dir then psc.add({ name = dir }) end
    end
    -- fallback: list current dir entries that are directories
    if #psc.glob("**/kustomization.yaml") == 0 then
        for _, e in ipairs(psc.ls(".") or {}) do
            if e.is_dir then
                psc.add({ name = e.name })
            end
        end
    end
end

local function add_yaml_files()
    for _, p in ipairs(psc.glob("**/*.yaml") or {}) do
        psc.add({ name = p })
    end
    for _, p in ipairs(psc.glob("**/*.yml") or {}) do
        psc.add({ name = p })
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

psc.on({
    { command = { "edit", "add", "resource" }, multiple = true },
    { command = { "edit", "remove", "resource" }, multiple = true },
    { command = { "edit", "add", "base" }, multiple = true },
    { command = "create" }
}, add_yaml_files)

psc.on({ option = "--namespace" }, add_namespaces)
