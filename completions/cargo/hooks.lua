local function token_value(name)
    local tokens = psc.tokens or {}
    for i, t in ipairs(tokens) do
        if t.type == "option" and t.name == name and tokens[i + 1] then
            return tokens[i + 1].input
        end
    end
end

local function manifest_path()
    return token_value("--manifest-path") or psc.path(token_value("-C") or ".", "Cargo.toml")
end

local function manifest_dir(path)
    return path:match("^(.*)[/\\]") or "."
end

local function cargo_args(args)
    local argv = { "cargo" }
    local dir = token_value("-C")
    if dir then
        argv[#argv + 1] = "-C"
        argv[#argv + 1] = dir
    end
    local manifest = token_value("--manifest-path")
    if manifest then
        argv[#argv + 1] = "--manifest-path"
        argv[#argv + 1] = manifest
    end
    for _, a in ipairs(args) do
        argv[#argv + 1] = a
    end
    return argv
end

local function add_packages()
    -- try cargo metadata first
    local meta = psc.run(cargo_args({ "metadata", "--format-version", "1", "--no-deps" }), { format = "json" })
    if meta and meta.packages then
        for _, pkg in ipairs(meta.packages) do
            if pkg.name then
                psc.add({ name = pkg.name, tip = pkg.version or "" })
            end
        end
        return
    end
    -- fallback: Cargo.toml
    local data = psc.toml(manifest_path())
    if not data then
        return
    end
    if data.package and data.package.name then
        psc.add({ name = data.package.name, tip = data.package.version or "package" })
    end
    -- workspace members
    if data.workspace and data.workspace.members then
        local base = manifest_dir(manifest_path())
        for _, m in ipairs(data.workspace.members) do
            -- member is a path, try to read its Cargo.toml
            local sub = psc.toml(psc.path(base, m, "Cargo.toml"))
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
    local data = psc.toml(manifest_path())
    if data and data.bin then
        for _, b in ipairs(data.bin) do
            if b.name then push(b.name, b.path or "bin") end
        end
    end
    local base = manifest_dir(manifest_path())
    for _, path in ipairs(psc.glob(psc.path(base, "src/bin/*.rs")) or {}) do
        push(path:match("([^/\\]+)%.rs$"), "src/bin")
    end
end

local function add_examples()
    local seen = {}
    local function push(name, tip)
        if not name or seen[name] then return end
        seen[name] = true
        psc.add({ name = name, tip = tip })
    end
    local data = psc.toml(manifest_path())
    if data and data.example then
        for _, e in ipairs(data.example) do
            if e.name then push(e.name, e.path or "example") end
        end
    end
    local base = manifest_dir(manifest_path())
    for _, path in ipairs(psc.glob(psc.path(base, "examples/*.rs")) or {}) do
        push(path:match("([^/\\]+)%.rs$"), "examples")
    end
end

local function add_features()
    local data = psc.toml(manifest_path())
    if not data then return end
    local seen = {}
    local function push(name, tip)
        if not name or seen[name] then return end
        seen[name] = true
        psc.add({ name = name, tip = tip })
    end
    for k, _ in pairs(data.features or {}) do
        push(k, "feature")
    end
    -- Optional dependencies are implicit features.
    for name, spec in pairs(data.dependencies or {}) do
        if type(spec) == "table" and spec.optional then
            push(name, "optional dependency")
        end
    end
end

local function add_deps()
    local data = psc.toml(manifest_path())
    if not data then return end
    local seen = {}
    local function add(tbl)
        if type(tbl) ~= "table" then return end
        for name, spec in pairs(tbl) do
            if not seen[name] then
                seen[name] = true
                local tip = type(spec) == "table" and spec.version or spec
                psc.add({ name = name, tip = tostring(tip or "dependency") })
            end
        end
    end
    add(data.dependencies)
    add(data["dev-dependencies"])
    add(data["build-dependencies"])
    if data.workspace then add(data.workspace.dependencies) end
end

local function add_installed_bins()
    for _, line in ipairs(psc.run({ "cargo", "install", "--list" }) or {}) do
        local name = line:match("^(%S+) v")
        if name then psc.add({ name = name, tip = line }) end
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

psc.on({ command = "remove", multiple = true }, add_deps)

psc.on({ command = "uninstall", multiple = true }, add_installed_bins)

psc.on({ option = "--package" }, add_packages)

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
