local function add_package_ids()
    -- local winget-pkgs manifests: manifests/<first-letter>/<publisher>/<package>/
    for _, p in ipairs(psc.glob("manifests/*/*/*") or {}) do
        local id = p:match("manifests/[^/\\]+/([^/\\]+/[^/\\]+)")
        if id then
            id = id:gsub("\\", "/")
            psc.add({ name = id, tip = p })
            if #completions > 200 then break end
        end
    end
    -- also try current directory package manifests
    for _, p in ipairs(psc.glob("*.yaml") or {}) do
        local n = p:match("([^/\\]+)$")
        if n then psc.add({ name = n, tip = p }) end
    end
end

local function add_versions()
    -- infer package id from earlier token if present
    local pkg
    for _, tok in ipairs(psc.tokens) do
        if tok.input:match("%.") and tok.input:match("%w+%.%w+") then
            pkg = tok.input
        end
    end
    if pkg then
        -- try winget show via komac list-versions or winget
        local lines = psc.run({ "komac", "list-versions", pkg })
        if lines then
            for _, line in ipairs(lines) do
                local v = line:match("(%d+%.[%d%.]+)")
                if v then psc.add({ name = v, tip = psc.trim(line) }) end
            end
            return
        end
        local wlines = psc.run({ "winget", "show", pkg })
        if wlines then
            for _, line in ipairs(wlines) do
                local v = line:match("Version:%s*(%S+)")
                if v then psc.add({ name = v, tip = line }) end
            end
        end
    end
    -- local manifests folder fallback
    if pkg then
        local pattern = "manifests/" .. pkg:gsub("%.", "/") .. "/*"
        for _, p in ipairs(psc.glob(pattern) or {}) do
            local n = p:match("([^/\\]+)$")
            if n then psc.add({ name = n, tip = p }) end
        end
    end
end

local function add_manifest_dirs()
    for _, p in ipairs(psc.glob("manifests/*") or {}) do
        local n = p:match("([^/\\]+)$")
        if n then psc.add({ name = p, tip = n }) end
    end
    local entries = psc.ls(".")
    if entries then
        for _, e in ipairs(entries) do
            if e.is_dir then psc.add({ name = e.name, tip = e.path }) end
        end
    end
end

psc.on({
    { command = "show" },
    { command = "list-versions" },
    { command = "update" },
    { command = "remove" }
}, add_package_ids)

psc.on({
    { option = "--version" },
    { option = "--replace" }
}, add_versions)

psc.on({ command = "submit" }, add_manifest_dirs)

psc.on({ command = "analyze" }, function()
    for _, p in ipairs(psc.glob("**/*.{exe,msi,msix}") or {}) do
        psc.add({ name = p, tip = "installer" })
        if #completions > 80 then break end
    end
end)
