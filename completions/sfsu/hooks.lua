local function get_scoop_root()
    return psc.env("SCOOP") or psc.env("SCOOP_GLOBAL")
end

local function add_installed()
    for _, line in ipairs(psc.run({ "sfsu", "list" }) or psc.run({ "scoop", "list" }, { shell = true }) or {}) do
        local name = line:match("^(%S+)")
        if name and not name:match("^Installed") and not name:match("^Name") and not name:match("^%-") then
            psc.add({ name = name, tip = psc.trim(line) })
        end
    end
    -- fallback: filesystem
    local root = get_scoop_root()
    if root then
        for _, e in ipairs(psc.ls(psc.path(root, "apps")) or {}) do
            if e.is_dir and e.name ~= "scoop" then psc.add({ name = e.name, tip = e.path }) end
        end
    end
end

local function add_all()
    local entries = {}
    local root = get_scoop_root()
    if root then
        for _, p in ipairs(psc.glob(psc.path(root, "buckets", "**/*.json")) or {}) do
            local name = p:match("([^/\\]+)%.json$")
            if name and name ~= "scoop" then entries[name] = p end
        end
        for n, p in pairs(entries) do
            psc.add({ name = n, tip = p })
        end
    end
    if next(entries) == nil then
        for _, line in ipairs(psc.run({ "sfsu", "search", "a" }) or {}) do
            local name = line:match("^(%S+)")
            if name then psc.add({ name = name, tip = line }) end
        end
    end
end

local function add_buckets()
    local root = get_scoop_root()
    if root then
        for _, e in ipairs(psc.ls(psc.path(root, "buckets")) or {}) do
            if e.is_dir then psc.add({ name = e.name, tip = e.path }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "sfsu", "bucket", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({ command = "list" }, add_installed)

psc.on({
    { command = "info" },
    { command = "cat" },
    { command = "depends" },
    { command = "home" },
    { command = "download" }
}, add_all)

psc.on({ command = "bucket" }, add_buckets)
