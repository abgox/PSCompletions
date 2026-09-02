local function add_jobs()
    local lines = psc.run({ "nomad", "job", "status" }) or {}
    for i, l in ipairs(lines) do
        if i == 1 and l:match("^ID") then
            -- skip header
        else
            local id = l:match("^(%S+)")
            if id and id ~= "" then
                psc.add({ name = id, tip = l })
            end
        end
    end
end

local function add_nodes()
    local lines = psc.run({ "nomad", "node", "status" }) or {}
    for i, l in ipairs(lines) do
        if i == 1 and l:match("^ID") then
            -- skip header
        else
            local id = l:match("^(%S+)")
            if id and id ~= "" then
                psc.add({ name = id, tip = l })
            end
        end
    end
end

local function add_allocs()
    local lines = psc.run({ "nomad", "alloc", "status" }) or {}
    -- fallback: allocation alias
    if not lines or #lines == 0 then
        lines = psc.run({ "nomad", "allocation", "status" }) or {}
    end
    for i, l in ipairs(lines) do
        if i == 1 and l:match("^ID") then
            -- skip header
        else
            local id = l:match("^(%S+)")
            if id and id ~= "" then
                psc.add({ name = id, tip = l })
            end
        end
    end
end

local function add_namespaces()
    for _, line in ipairs(psc.run({ "nomad", "namespace", "list" }) or {}) do
        local ns = line:match("^(%S+)")
        if ns and ns ~= "Name" and ns ~= "----" then
            psc.add({ name = ns, tip = "namespace" })
        end
    end
end

local function add_deployments()
    for _, line in ipairs(psc.run({ "nomad", "deployment", "list" }) or {}) do
        local id = line:match("^(%S+)")
        if id and not id:match("^ID") and id ~= "No" then
            psc.add({ name = id, tip = line })
        end
    end
end

psc.on({
    { command = { "job", "status" } },
    { command = { "job", "allocs" } },
    { command = { "job", "deployments" } },
    { command = { "job", "dispatch" } },
    { command = { "job", "eval" } },
    { command = { "job", "history" } },
    { command = { "job", "inspect" } },
    { command = { "job", "periodic" } },
    { command = { "job", "plan" } },
    { command = { "job", "promote" } },
    { command = { "job", "restart" } },
    { command = { "job", "revert" } },
    { command = { "job", "run" } },
    { command = { "job", "scale" } },
    { command = { "job", "scaling-events" } },
    { command = { "job", "start" } },
    { command = { "job", "stop" } },
    { command = { "job", "tag" } },
    { command = { "job", "validate" } },
    { command = { "job", "action" } },
    { command = "status", multiple = true },
    { command = "stop", multiple = true },
    { command = "run" }
}, add_jobs)

psc.on({
    { command = { "node", "status" } },
    { command = { "node", "config" } },
    { command = { "node", "drain" } },
    { command = { "node", "eligibility" } },
    { command = { "node", "identity" } },
    { command = { "node", "meta" } },
    { command = { "node", "pool" } }
}, add_nodes)

psc.on({
    { command = { "allocation", "status" } },
    { command = { "allocation", "checks" } },
    { command = { "allocation", "exec" } },
    { command = { "allocation", "fs" } },
    { command = { "allocation", "logs" } },
    { command = { "allocation", "pause" } },
    { command = { "allocation", "restart" } },
    { command = { "allocation", "signal" } },
    { command = { "allocation", "stop" } },
    { command = "exec" }
}, add_allocs)

psc.on({
    { option = "-namespace" },
    { command = { "namespace", "status" } },
    { command = { "namespace", "inspect" } },
    { command = { "namespace", "delete" } }
}, add_namespaces)

psc.on({
    { command = { "deployment", "status" } },
    { command = { "deployment", "pause" } },
    { command = { "deployment", "resume" } },
    { command = { "deployment", "fail" } },
    { command = { "deployment", "promote" } },
    { command = { "deployment", "unblock" } }
}, add_deployments)
