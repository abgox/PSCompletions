local function add_secrets_engines()
    local data = psc.run({ "vault", "secrets", "list", "-format=json" }, { format = "json" })
    if data and type(data) == "table" then
        for k, v in pairs(data) do
            local tip = ""
            if type(v) == "table" and v.type then tip = v.type end
            -- keys end with /
            psc.add({ name = k, tip = tip })
            -- also without trailing slash
            local short = k:gsub("/$", "")
            if short ~= k then psc.add({ name = short, tip = tip }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "vault", "secrets", "list" }) or {}) do
        local path = line:match("^(%S+)")
        if path and path ~= "Path" and not path:match("^%-") then
            psc.add({ name = path, tip = line })
        end
    end
end

local function add_auth_methods()
    local data = psc.run({ "vault", "auth", "list", "-format=json" }, { format = "json" })
    if data and type(data) == "table" then
        for k, v in pairs(data) do
            local tip = type(v) == "table" and (v.type or "") or ""
            psc.add({ name = k, tip = tip })
            local short = k:gsub("/$", "")
            if short ~= k then psc.add({ name = short, tip = tip }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "vault", "auth", "list" }) or {}) do
        local path = line:match("^(%S+)")
        if path and path ~= "Path" then psc.add({ name = path, tip = line }) end
    end
end

local function add_policies()
    local data = psc.run({ "vault", "policy", "list", "-format=json" }, { format = "json" })
    if data and type(data) == "table" then
        -- may be array or map
        if #data > 0 then
            for _, p in ipairs(data) do psc.add({ name = p }) end
        else
            for k, _ in pairs(data) do psc.add({ name = k }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "vault", "policy", "list" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" then psc.add({ name = name }) end
    end
end

local function add_kv_paths()
    -- try vault kv list for secret/ mount; fallback to vault list
    local prefix = "secret/"
    -- if current word has a path, use it
    local cur = psc.typing and psc.typing.input or ""
    if cur ~= "" and not cur:match("^%-") then
        -- use what user typed as prefix if it contains /
        if cur:match("/") then prefix = cur:match("^(.*/)") or cur end
    end
    local data = psc.run({ "vault", "kv", "list", "-format=json", prefix }, { format = "json" })
    if data and type(data) == "table" then
        for _, p in ipairs(data) do
            psc.add({ name = prefix .. p, tip = "kv" })
        end
        return
    end
    for _, line in ipairs(psc.run({ "vault", "kv", "list", prefix }) or {}) do
        local name = psc.trim(line)
        if name ~= "" and name ~= "Keys" and not name:match("^%-") then
            psc.add({ name = prefix .. name, tip = "kv" })
        end
    end
end

psc.on({
    { command = { "secrets", "disable" } },
    { command = { "secrets", "move" } },
    { command = { "secrets", "tune" } }
}, add_secrets_engines)

psc.on({
    { command = { "auth", "disable" } },
    { command = { "auth", "move" } },
    { command = { "auth", "tune" } }
}, add_auth_methods)

psc.on({
    { command = { "policy", "delete" } },
    { command = { "policy", "read" } },
    { command = { "policy", "write" } },
    { command = { "policy", "fmt" } }
}, add_policies)

psc.on({
    { command = { "kv", "get" } },
    { command = { "kv", "put" } },
    { command = { "kv", "delete" } },
    { command = { "kv", "destroy" } },
    { command = { "kv", "list" } },
    { command = { "kv", "metadata" } },
    { command = { "kv", "patch" } },
    { command = { "kv", "get" }, multiple = true },
    { command = { "kv", "put" }, multiple = true }
}, add_kv_paths)

psc.on({
    { command = "read",   multiple = true },
    { command = "write",  multiple = true },
    { command = "delete", multiple = true },
    { command = "list",   multiple = true },
    { command = "patch",  multiple = true }
}, function()
    add_secrets_engines()
    add_kv_paths()
end)
