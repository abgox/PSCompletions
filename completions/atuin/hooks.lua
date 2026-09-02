local function add_history()
    for _, line in ipairs(psc.run({ "atuin", "history", "list", "--cmd-only" }) or {}) do
        local cmd = psc.trim(line)
        if cmd ~= "" then psc.add({ name = cmd, tip = "history" }) end
    end
end

local function add_scripts()
    for _, line in ipairs(psc.run({ "atuin", "scripts", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "NAME" and not name:match("^%-") then
            psc.add({ name = name, tip = line })
        end
    end
end

local function add_kv_keys()
    for _, line in ipairs(psc.run({ "atuin", "kv", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "KEY" then psc.add({ name = name, tip = line }) end
    end
end

local function add_aliases()
    for _, line in ipairs(psc.run({ "atuin", "dotfiles", "alias", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "NAME" then psc.add({ name = name, tip = line }) end
    end
end

local function add_vars()
    for _, line in ipairs(psc.run({ "atuin", "dotfiles", "var", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "NAME" then psc.add({ name = name, tip = line }) end
    end
end

psc.on({ command = "search" }, add_history)

psc.on({
    { command = { "scripts", "delete" } },
    { command = { "scripts", "edit" } },
    { command = { "scripts", "get" } },
    { command = { "scripts", "run" } }
}, add_scripts)

psc.on({
    { command = { "kv", "get" } },
    { command = { "kv", "delete" } },
    { command = { "kv", "set" } }
}, add_kv_keys)

psc.on({ command = { "dotfiles", "alias", "delete" } }, add_aliases)

psc.on({ command = { "dotfiles", "var", "delete" } }, add_vars)
