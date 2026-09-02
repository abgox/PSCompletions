local function add_releases()
    -- helmfile list prints releases; try json output first
    local data = psc.run({ "helmfile", "list", "-o", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, r in ipairs(data) do
            local name = r.name or r.Name or r.release
            if name then
                psc.add({ name = name })
            end
        end
        if #data > 0 then return end
    end
    for _, l in ipairs(psc.run({ "helmfile", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^NAME") and not l:match("^%-%-") then
            local name = l:match("^(%S+)")
            if name then
                psc.add({ name = name })
            end
        end
    end
    -- fallback: parse helmfile.yaml for releases[].name
    if #psc.run({ "helmfile", "list" }) == 0 then
        local cfg = psc.yaml("helmfile.yaml") or psc.yaml("helmfile.yaml.gotmpl") or psc.yaml("helmfile.yml")
        if cfg and type(cfg.releases) == "table" then
            for _, r in ipairs(cfg.releases) do
                if r and r.name then
                    psc.add({ name = r.name })
                end
            end
        end
    end
end

local function add_namespaces()
    for _, l in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
        local n = l:match("^namespace/(.*)$") or l
        if n and n ~= "" then
            psc.add({ name = n })
        end
    end
end

local function add_contexts()
    psc.add(psc.items(psc.run({ "kubectl", "config", "get-contexts", "-o", "name" }) or {}))
end

psc.on({
    { command = "apply", multiple = true },
    { command = "diff", multiple = true },
    { command = "sync", multiple = true },
    { command = "destroy", multiple = true },
    { command = "template", multiple = true },
    { command = "lint", multiple = true },
    { command = "status", multiple = true }
}, add_releases)

psc.on({ option = "--namespace" }, add_namespaces)

psc.on({ option = "--kube-context" }, add_contexts)
