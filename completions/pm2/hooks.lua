local function add_processes()
    -- pm2 jlist returns JSON array of processes
    local data = psc.run({ "pm2", "jlist" }, { format = "json" })
    if data and type(data) == "table" and #data > 0 then
        local seen = {}
        for _, proc in ipairs(data) do
            local name = proc.name
            local pid = proc.pid
            local pm_id = proc.pm_id
            if pm_id ~= nil then pm_id = tostring(pm_id) end
            if name and not seen[name] then
                seen[name] = true
                local tip = "pm2 process"
                if pid then tip = tip .. " pid:" .. tostring(pid) end
                if pm_id then tip = tip .. " id:" .. pm_id end
                psc.add({ name = name, tip = tip })
            end
            if pm_id and not seen[pm_id] then
                seen[pm_id] = true
                psc.add({ name = pm_id, tip = name and ("process " .. name) or "pm_id" })
            end
        end
        return
    end
    -- fallback: pm2 list parsed as lines
    local lines = psc.run({ "pm2", "list" })
    if not lines then return end
    for _, line in ipairs(lines) do
        -- lines contain process names; skip header/separators
        local t = psc.trim(line)
        if t ~= "" and not t:match("^%+%-") and not t:match("^│") then
            -- naive fallback: add tokens that look like names
            for tok in t:gmatch("%S+") do
                if tok:match("^[%w%-_%.]+$") and #tok > 1 then
                    psc.add({ name = tok })
                end
            end
        end
    end
end

local function add_namespaces()
    local data = psc.run({ "pm2", "jlist" }, { format = "json" })
    if not data then return end
    local seen = {}
    for _, proc in ipairs(data) do
        local ns = proc.namespace or proc.ns
        if ns and not seen[ns] then
            seen[ns] = true
            psc.add({ name = ns, tip = "namespace" })
        end
    end
end

local function add_ecosystem_files()
    for _, p in ipairs(psc.glob("ecosystem.config.*") or {}) do
        psc.add({ name = p, tip = p })
    end
    for _, p in ipairs(psc.glob("pm2.config.*") or {}) do
        psc.add({ name = p, tip = p })
    end
    for _, p in ipairs(psc.glob("*.config.js") or {}) do
        psc.add({ name = p, tip = p })
    end
end

psc.on({
    { command = "delete" },
    { command = "describe" },
    { command = "restart" },
    { command = "reload" },
    { command = "stop" },
    { command = "reset" },
    { command = "inspect" },
    { command = "env" },
    { command = "id" },
    { command = "pid" },
    { command = "attach" },
    { command = "trigger" },
    { command = "sendSignal" },
    { command = "scale" },
    { command = "logs" },
    { command = "flush" },
    { command = "forward" },
    { command = "backward" },
    { command = "pull" },
    { command = "monitor" },
    { command = "unmonitor" },
    { command = "send" },
    { option = "--only" }
}, add_processes)

psc.on({ option = "--namespace" }, add_namespaces)

psc.on({
    { command = "deploy" },
    { command = "startOrReload" },
    { command = "startOrRestart" },
    { command = "startOrGracefulReload" }
}, add_ecosystem_files)
