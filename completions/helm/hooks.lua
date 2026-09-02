local function add_releases()
    -- helm list -q prints release names, one per line
    local lines = psc.run({ "helm", "list", "-q" }) or {}
    if #lines > 0 then
        -- filter empty and header if any
        local out = {}
        for _, l in ipairs(lines) do
            l = psc.trim(l)
            if l ~= "" then
                table.insert(out, l)
            end
        end
        psc.add(psc.items(out))
        return
    end
    -- fallback: helm list --output json if available
    local data = psc.run({ "helm", "list", "-o", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, r in ipairs(data) do
            if r and r.name then
                psc.add({ name = r.name })
            end
        end
    end
end

local function add_charts()
    -- helm search repo lists charts; parse first column
    local lines = psc.run({ "helm", "search", "repo" }) or {}
    for i, l in ipairs(lines) do
        if i == 1 and l:match("^NAME") then
            -- skip header
        else
            local chart = l:match("^(%S+)")
            if chart and chart ~= "" then
                psc.add({ name = chart })
            end
        end
    end
end

local function add_repos()
    local lines = psc.run({ "helm", "repo", "list" }) or {}
    for i, l in ipairs(lines) do
        if i == 1 and l:match("^NAME") then
            -- skip header
        else
            local repo = l:match("^(%S+)")
            if repo and repo ~= "" then
                psc.add({ name = repo })
            end
        end
    end
    -- fallback json format
    if #lines == 0 then
        local data = psc.run({ "helm", "repo", "list", "-o", "json" }, { format = "json" })
        if data and type(data) == "table" then
            for _, r in ipairs(data) do
                if r and r.name then
                    psc.add({ name = r.name })
                end
            end
        end
    end
end

local function add_namespaces()
    for _, l in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
        local n = l:match("^namespace/(.*)$") or l
        if n and n ~= "" then
            psc.add({ name = n })
        end
    end
end

local function add_contexts()
    local lines = psc.run({ "kubectl", "config", "get-contexts", "-o", "name" }) or {}
    psc.add(psc.items(lines or {}))
end

psc.on({
    { command = "uninstall" },
    { command = "upgrade" },
    { command = "status" },
    { command = "history" },
    { command = "rollback" },
    { command = "test" },
    { command = "get" },
    { command = { "get", "all" }, multiple = true },
    { command = { "get", "hooks" }, multiple = true },
    { command = { "get", "manifest" }, multiple = true },
    { command = { "get", "metadata" }, multiple = true },
    { command = { "get", "notes" }, multiple = true },
    { command = { "get", "values" }, multiple = true }
}, add_releases)

psc.on({
    { command = "install" },
    { command = "template" },
    { command = "pull" },
    { command = "show" },
    { command = { "show", "all" } },
    { command = { "show", "chart" } },
    { command = { "show", "crds" } },
    { command = { "show", "readme" } },
    { command = { "show", "values" } },
    { command = { "search", "repo" } },
    { command = { "search", "hub" } }
}, add_charts)

psc.on({
    { command = { "repo", "remove" } },
    { command = { "repo", "update" } }
}, add_repos)

psc.on({ option = "--namespace" }, add_namespaces)

psc.on({ option = "--kube-context" }, add_contexts)

psc.on({ option = "--kubeconfig" }, function()
    local home = psc.env("USERPROFILE") or psc.env("HOME")
    if home then
        local dir = psc.path(home, ".kube")
        for _, e in ipairs(psc.ls(dir) or {}) do
            if not e.is_dir then
                psc.add({ name = e.path })
            end
        end
    end
end)
