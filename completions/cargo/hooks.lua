local function add_packages()
    -- try cargo metadata first
    local meta = psc.run({ "cargo", "metadata", "--format-version", "1", "--no-deps" }, { format = "json" })
    if meta and meta.packages then
        for _, pkg in ipairs(meta.packages) do
            if pkg.name then
                psc.add({ name = pkg.name, tip = pkg.version or "" })
            end
        end
        return
    end
    -- fallback: Cargo.toml
    local data = psc.toml("Cargo.toml")
    if not data then
        return
    end
    if data.package and data.package.name then
        psc.add({ name = data.package.name, tip = data.package.version or "package" })
    end
    -- workspace members
    if data.workspace and data.workspace.members then
        for _, m in ipairs(data.workspace.members) do
            -- member is a path, try to read its Cargo.toml
            local sub = psc.toml(psc.path(m, "Cargo.toml"))
            if sub and sub.package and sub.package.name then
                psc.add({ name = sub.package.name, tip = sub.package.version or "workspace" })
            end
        end
    end
end

local function add_bins()
    local seen = {}
    local function push(name, tip)
        if not name or seen[name] then return end
        seen[name] = true
        psc.add({ name = name, tip = tip })
    end
    local data = psc.toml("Cargo.toml")
    if data and data.bin then
        for _, b in ipairs(data.bin) do
            if b.name then push(b.name, b.path or "bin") end
        end
    end
    for _, p in ipairs(psc.glob("src/bin/*.rs") or {}) do
        local n = p:match("([^/\\]+)%.rs$")
        if n then push(n, p) end
    end
end

local function add_examples()
    local seen = {}
    local function push(name, tip)
        if not name or seen[name] then return end
        seen[name] = true
        psc.add({ name = name, tip = tip })
    end
    local data = psc.toml("Cargo.toml")
    if data and data.example then
        for _, e in ipairs(data.example) do
            if e.name then push(e.name, e.path or "example") end
        end
    end
    for _, p in ipairs(psc.glob("examples/**/*.rs") or {}) do
        local n = p:match("([^/\\]+)%.rs$")
        if n then push(n, p) end
    end
end

local function add_features()
    local data = psc.toml("Cargo.toml")
    if not data or not data.features then return end
    for k, _ in pairs(data.features) do
        psc.add({ name = k, tip = "feature" })
    end
end

local function add_targets()
    local lines = psc.run({ "rustup", "target", "list" }) or {}
    for _, line in ipairs(lines) do
        -- rustup target list prints "<triple> <status>"
        local t = line:match("^(%S+)")
        if t then psc.add({ name = t, tip = line }) end
    end
end

psc.on({ option = "--bin" }, add_bins)

psc.on({ option = "--example" }, add_examples)

psc.on({ option = "--features" }, add_features)

psc.on({ option = "--target" }, add_targets)

psc.on({
    { command = "remove" },
    { command = "uninstall" },
    { option = "--package" }
}, add_packages)
