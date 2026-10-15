local function add_skills()
    local block_start = true
    for _, line in ipairs(psc.run({ "android", "skills", "list" }) or {}) do
        if line:match("^%s*$") then
            block_start = true
        else
            local name = line:match("^([a-z0-9][a-z0-9%-]*)$")
            if block_start and name then
                psc.add({ name = name })
            end
            block_start = false
        end
    end
end

local function add_sdk_packages()
    -- install takes available packages; the list pattern matches either section
    local only_available = psc.token({ name = "install", type = "command" }) ~= nil
    local available = false
    for _, line in ipairs(psc.run({ "android", "sdk", "list", "--all" }) or {}) do
        if line:match("^Available packages:%s*$") then
            available = true
        elseif line:match("^%S") then
            available = false
        elseif available or not only_available then
            local pkg = line:match("^%s+(%S+)")
            if pkg then
                psc.add({ name = pkg })
            end
        end
    end
end

local function add_sdk_installed()
    for _, line in ipairs(psc.run({ "android", "sdk", "list" }) or {}) do
        local pkg = line:match("^%s+(%S+)")
        if pkg then
            psc.add({ name = pkg })
        end
    end
end

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)

psc.on({
    { command = { "skills", "add" } },
    { command = { "skills", "remove" } },
    { command = { "skills", "update" } },
}, add_skills)

psc.on({
    { command = { "sdk", "install" } },
    { command = { "sdk", "list" } },
}, add_sdk_packages)

psc.on({
    { command = { "sdk", "remove" } },
    { command = { "sdk", "update" } },
}, add_sdk_installed)
