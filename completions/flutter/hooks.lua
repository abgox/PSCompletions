local function add_devices()
    -- json format gives structured device list
    local data = psc.run({ "flutter", "devices", "--machine" }, { format = "json" })
    if data then
        -- --machine returns array of device tables
        local list = data
        -- handle wrapped object case
        if data.devices then list = data.devices end
        for _, d in ipairs(list or {}) do
            if type(d) == "table" and d.id then
                local name = d.name or d.id
                local tip = (d.platform or "") .. " " .. (d.name or "")
                psc.add({ name = d.id, tip = psc.trim(tip) })
                -- also add name as alias if distinct
                if d.name and d.name ~= d.id then
                    psc.add({ name = d.name, tip = d.id })
                end
            end
        end
        return
    end
    -- fallback: plain lines
    for _, line in ipairs(psc.run({ "flutter", "devices" }) or {}) do
        local id = line:match("(%S+)%s+•")
        if id then psc.add({ name = id, tip = line }) end
    end
end

local function add_emulators()
    local lines = psc.run({ "flutter", "emulators" }) or {}
    for _, line in ipairs(lines) do
        local id = line:match("(%S+)%s+•")
        if id and id ~= "id" then psc.add({ name = id, tip = line }) end
    end
    -- also try json format
    local data = psc.run({ "flutter", "emulators", "--machine" }, { format = "json" })
    if data then
        for _, e in ipairs(data or {}) do
            if type(e) == "table" and e.id then
                psc.add({ name = e.id, tip = e.name or "" })
            end
        end
    end
end

psc.on({ option = "--device-id" }, add_devices)

psc.on({ command = "emulators" }, add_emulators)
