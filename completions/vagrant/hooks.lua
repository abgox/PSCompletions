local function add_boxes()
    for _, line in ipairs(psc.run({ "vagrant", "box", "list" }) or {}) do
        -- "ubuntu/jammy64 (virtualbox, 20240101)"
        local name = line:match("^(%S+)")
        if name and not name:match("^There") then
            psc.add({ name = name, tip = line })
        end
    end
end

local function add_plugins()
    for _, line in ipairs(psc.run({ "vagrant", "plugin", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_machines()
    for _, line in ipairs(psc.run({ "vagrant", "global-status" }) or {}) do
        -- global-status table rows
        local id = line:match("^(%x+)%s+")
        if id then
            local name = line:match("^%x+%s+([%w%-%_]+)")
            if name then psc.add({ name = name, tip = line }) end
        end
    end
    -- fallback: Vagrantfile hint
    if psc.exist("Vagrantfile") then
        psc.add({ name = "default", tip = "Vagrantfile" })
    end
end

psc.on({
    { command = { "box", "remove" } },
    { command = { "box", "repackage" } },
    { command = "init" }
}, add_boxes)

psc.on({
    { command = { "plugin", "uninstall" } },
    { command = { "plugin", "update" } }
}, add_plugins)

psc.on({
    { command = "halt" },
    { command = "destroy" },
    { command = "ssh" },
    { command = "reload" },
    { command = "up" },
    { command = "provision" }
}, add_machines)
