local function add_outputs()
    local data = psc.run({ "terragrunt", "output", "-json" }, { format = "json" })
    if data and type(data) == "table" then
        for k, v in pairs(data) do
            local tip = ""
            if type(v) == "table" and v.value ~= nil then
                tip = tostring(v.value)
            end
            psc.add({ name = k, tip = tip })
        end
        return
    end
    for _, line in ipairs(psc.run({ "terragrunt", "output" }) or {}) do
        local name = line:match("^(%S+)%s*=")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_resources()
    for _, line in ipairs(psc.run({ "terragrunt", "state", "list" }) or {}) do
        local addr = psc.trim(line)
        if addr ~= "" then
            psc.add({ name = addr, tip = "resource" })
        end
    end
end

local function add_units()
    for _, p in ipairs(psc.glob("**/terragrunt.hcl") or {}) do
        psc.add({ name = p, tip = "unit" })
    end
    -- also top-level hcl files
    for _, p in ipairs(psc.glob("*.hcl") or {}) do
        psc.add({ name = p, tip = "unit" })
    end
end

psc.on({
    { command = "output", multiple = true },
    { command = "output" }
}, add_outputs)

psc.on({
    { command = "import", multiple = true },
    { option = "-target" },
    { option = "-replace" }
}, add_resources)

psc.on({
    { command = { "backend", "migrate" }, multiple = true },
    { command = { "backend", "bootstrap" } },
    { command = { "backend", "delete" } },
    { command = "find", multiple = true },
    { command = "list", multiple = true },
    { command = { "dag", "graph" } },
    { command = "init", multiple = true },
    { command = "plan", multiple = true },
    { command = "apply", multiple = true },
    { command = "destroy", multiple = true },
    { option = "--config" }
}, add_units)

psc.on({ option = "--tf-path" }, function()
    psc.add({ name = "terraform", tip = "terraform binary" })
    psc.add({ name = "tofu", tip = "opentofu binary" })
end)
