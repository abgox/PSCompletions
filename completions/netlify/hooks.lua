local function add_sites()
    for _, line in ipairs(psc.run({ "netlify", "sites:list" }) or {}) do
        local name = line:match("(%S+)%.netlify%.app") or line:match("^(%S+)")
        if name and name ~= "Sites:" and not name:match("^%-") then
            psc.add({ name = name, tip = line })
        end
    end
    -- json fallback
    local data = psc.run({ "netlify", "api", "listSites" }, { format = "json" })
    if type(data) == "table" then
        for _, s in ipairs(data) do
            if s.name then psc.add({ name = s.name, tip = s.url or s.id or "" }) end
        end
    end
end

local function add_env_vars()
    for _, line in ipairs(psc.run({ "netlify", "env:list" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "Keys:" then psc.add({ name = name, tip = line }) end
    end
end

local function add_functions()
    for _, e in ipairs(psc.ls("netlify/functions") or {}) do
        psc.add({ name = e.name, tip = e.path })
    end
    for _, e in ipairs(psc.ls("functions") or {}) do
        psc.add({ name = e.name, tip = e.path })
    end
end

psc.on({
    { command = { "env", "get" } },
    { command = { "env", "unset" } },
    { command = { "env", "set" } }
}, add_env_vars)

psc.on({
    { option = "--site" },
    { command = "link" }
}, add_sites)

psc.on({ command = { "functions", "invoke" } }, add_functions)
