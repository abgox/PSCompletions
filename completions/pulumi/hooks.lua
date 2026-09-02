local function add_stacks()
    local data = psc.run({ "pulumi", "stack", "ls", "--json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, s in ipairs(data) do
            local name = s.name or s.stackName or s.stack
            if name then
                local tip = s.lastUpdate or s.resourceCount or ""
                if type(tip) == "number" then tip = tostring(tip) .. " resources" end
                psc.add({ name = name, tip = tip })
            end
        end
        return
    end
    for _, line in ipairs(psc.run({ "pulumi", "stack", "ls" }) or {}) do
        if not line:match("^NAME") and not line:match("^%s*$") then
            local name = line:match("^(%S+)")
            if name then psc.add({ name = name, tip = line }) end
        end
    end
end

local function add_configs()
    -- try Pulumi.yaml for config keys, then pulumi config --json
    local data = psc.run({ "pulumi", "config", "--json" }, { format = "json" })
    -- some versions need stack flag; try without
    if not data then
        data = psc.run({ "pulumi", "config", "--show-secrets=false", "--json" }, { format = "json" })
    end
    if data and type(data) == "table" then
        for k, v in pairs(data) do
            local tip = type(v) == "table" and (v.value or "") or tostring(v)
            psc.add({ name = k, tip = tip })
        end
        return
    end
    -- fallback: read Pulumi.yaml
    local yaml = psc.yaml("Pulumi.yaml")
    if yaml and yaml.config then
        for k, _ in pairs(yaml.config) do
            psc.add({ name = k, tip = "config" })
        end
    end
end

local function add_urns()
    -- pulumi stack --json gives resources with urn
    local data = psc.run({ "pulumi", "stack", "--json" }, { format = "json" })
    if data and data.resources then
        for _, r in ipairs(data.resources) do
            if r.urn then psc.add({ name = r.urn, tip = r.type or "" }) end
        end
    end
end

psc.on({
    { command = { "stack", "select" } },
    { command = { "stack", "remove" } },
    { command = { "stack", "rename" } },
    { command = { "stack", "export" } },
    { command = { "stack", "import" } },
    { command = { "stack", "graph" } },
    { command = { "stack", "output" } },
    { command = { "stack", "history" } },
    { command = { "stack", "tag" } },
    { command = { "stack", "change-secrets-provider" } },
    { command = "preview", multiple = true },
    { command = "update", multiple = true },
    { command = "refresh", multiple = true },
    { command = "destroy", multiple = true },
    { command = "stack", multiple = true },
    { option = "--stack" },
    { option = "-s" }
}, add_stacks)

psc.on({
    { command = { "config", "get" } },
    { command = { "config", "set" } },
    { command = { "config", "rm" } },
    { command = { "config", "remove" } },
    { command = { "config", "copy" } }
}, add_configs)

psc.on({
    { command = { "state", "move" }, multiple = true },
    { command = { "state", "remove" }, multiple = true },
    { command = { "state", "protect" }, multiple = true },
    { command = { "state", "unprotect" }, multiple = true },
    { command = { "state", "rename" }, multiple = true }
}, add_urns)
