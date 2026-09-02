local function add_clusters()
    -- prefer json output
    local data = psc.run({ "k3d", "cluster", "list", "-o", "json" }, { format = "json" })
    if data and type(data) == "table" then
        -- k3d json is array of clusters or object with clusters field
        local list = data
        if data.clusters then list = data.clusters end
        for _, c in ipairs(list) do
            -- cluster entries may be string or {name}
            local name = type(c) == "table" and c.name or tostring(c)
            if name and name ~= "" then psc.add({ name = name }) end
        end
        if #list > 0 then return end
    end
    for _, l in ipairs(psc.run({ "k3d", "cluster", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^NAME") and not l:match("^%-%-") then
            local name = l:match("^(%S+)")
            if name then
                psc.add({ name = name })
            end
        end
    end
end

local function add_nodes()
    local data = psc.run({ "k3d", "node", "list", "-o", "json" }, { format = "json" })
    if data and type(data) == "table" then
        local list = data
        if data.nodes then list = data.nodes end
        for _, n in ipairs(list) do
            local name = type(n) == "table" and n.name or tostring(n)
            if name and name ~= "" then psc.add({ name = name }) end
        end
        if #list > 0 then return end
    end
    for _, l in ipairs(psc.run({ "k3d", "node", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^NAME") then
            local name = l:match("^(%S+)")
            if name then
                psc.add({ name = name })
            end
        end
    end
end

local function add_registries()
    for _, l in ipairs(psc.run({ "k3d", "registry", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^NAME") then
            local name = l:match("^(%S+)")
            if name then
                psc.add({ name = name })
            end
        end
    end
end

psc.on({
    { command = { "cluster", "delete" }, multiple = true },
    { command = { "cluster", "start" }, multiple = true },
    { command = { "cluster", "stop" }, multiple = true },
    { command = { "cluster", "list" }, multiple = true },
    { command = { "cluster", "restart" }, multiple = true },
    { command = { "cluster", "update" } },
    { command = { "kubeconfig", "merge" }, multiple = true },
    { command = { "kubeconfig", "print" }, multiple = true },
    { command = { "images", "import" } },
    { option = "--cluster" }
}, add_clusters)

psc.on({
    { command = { "node", "delete" }, multiple = true },
    { command = { "node", "list" }, multiple = true },
    { command = { "node", "start" } },
    { command = { "node", "stop" } },
    { command = { "node", "create" } },
    { command = { "node", "update" } }
}, add_nodes)

psc.on({
    { command = { "registries", "delete" }, multiple = true },
    { command = { "registries", "list" }, multiple = true },
    { command = { "registries", "create" } }
}, add_registries)
