local function add_profiles()
    local data = psc.run({ "minikube", "profile", "list", "-o", "json" }, { format = "json" })
    if type(data) ~= "table" then return end
    local profiles = data.valid or data.profiles or data
    if type(profiles) ~= "table" then return end
    -- profile entries may be string or {Name/name}
    for _, p in ipairs(profiles) do
        local name = type(p) == "table" and (p.Name or p.name) or tostring(p)
        if name and name ~= "" then psc.add({ name = name }) end
    end
end

local function add_addons()
    local data = psc.run({ "minikube", "addons", "list", "-o", "json" }, { format = "json" })
    if type(data) ~= "table" then return end
    for k, _ in pairs(data) do
        if k and k ~= "" then psc.add({ name = k }) end
    end
    for _, v in ipairs(data) do
        local name = type(v) == "table" and v.name or tostring(v)
        if name and name ~= "" then psc.add({ name = name }) end
    end
end

local function add_nodes()
    for _, l in ipairs(psc.run({ "minikube", "node", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^%-") and not l:match("^Name") then
            local n = l:match("^(%S+)")
            if n then psc.add({ name = n }) end
        end
    end
end

local function add_contexts()
    psc.add(psc.items(psc.run({ "kubectl", "config", "get-contexts", "-o", "name" }) or {}))
end

local function add_namespaces()
    for _, l in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
        local n = l:match("^namespace/(.*)$") or l
        if n and n ~= "" then psc.add({ name = n }) end
    end
end

psc.on({
    { command = "profile" },
    { option = "--profile" }
}, add_profiles)

psc.on({
    { command = { "addons", "configure" } },
    { command = { "addons", "disable" } },
    { command = { "addons", "enable" } },
    { command = { "addons", "images" } },
    { command = { "addons", "open" } }
}, add_addons)

psc.on({
    { command = { "node", "delete" } },
    { command = { "node", "start" } },
    { command = { "node", "stop" } },
    { option = "--node" }
}, add_nodes)

psc.on({ option = "--namespace" }, add_namespaces)

-- kubectl contexts double as profiles: each profile lands in kubeconfig as a context.
psc.on({ option = "--profile" }, add_contexts)
