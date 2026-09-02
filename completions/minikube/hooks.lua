local function add_profiles()
    local data = psc.run({ "minikube", "profile", "list", "-o", "json" }, { format = "json" })
    if data and type(data) == "table" then
        local profiles = data.valid or data.profiles or data
        if type(profiles) == "table" then
            for _, p in ipairs(profiles) do
                -- profile entries may be string or {Name/name}
                local name = type(p) == "table" and (p.Name or p.name) or tostring(p)
                if name and name ~= "" then psc.add({ name = name }) end
            end
            if #profiles > 0 then return end
        end
    end
    for _, l in ipairs(psc.run({ "minikube", "profile", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^|") and not l:match("^%-") and not l:match("^Profile") and not l:match("^\\*") then
            local name = l:match("^%*?%s*(%S+)")
            if name and name ~= "Profile" and name ~= "Name" then
                psc.add({ name = name })
            end
        end
    end
end

local function add_addons()
    local data = psc.run({ "minikube", "addons", "list", "-o", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for k, _ in pairs(data) do
            if k and k ~= "" then psc.add({ name = k }) end
        end
        -- also handle array form
        for _, v in ipairs(data) do
            local name = type(v) == "table" and v.name or tostring(v)
            if name and name ~= "" then psc.add({ name = name }) end
        end
        return
    end
    for _, l in ipairs(psc.run({ "minikube", "addons", "list" }) or {}) do
        l = psc.trim(l)
        if l ~= "" and not l:match("^%-") then
            local addon = l:match("^|%s*(%S+)") or l:match("^(%S+)")
            if addon and addon ~= "" and addon ~= "Addon" then
                -- strip status column
                addon = addon:gsub("%|.*", "")
                addon = psc.trim(addon)
                if addon:match("^[%w%-]+$") then
                    psc.add({ name = addon })
                end
            end
        end
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
    { command = { "profile", "list" } },
    { command = "start" },
    { command = "delete" },
    { command = "stop" },
    { command = "status" },
    { command = "pause" },
    { command = "unpause" },
    { command = "update-context" },
    { command = "ssh" },
    { command = "ip" },
    { command = "logs" },
    { command = "mount" },
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
    { command = { "node", "list" } }
}, add_nodes)

psc.on({ option = "--namespace" }, add_namespaces)

psc.on({ option = "--context" }, add_contexts)
