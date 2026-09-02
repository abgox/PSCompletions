local function add_branches()
    for _, b in ipairs(psc.run({ "git", "branch", "--format=%(refname:lstrip=2)" }) or {}) do
        if not b:match("^%(.+ detach") then
            psc.add({ name = b, tip = "branch" })
        end
    end
    -- also remote branches
    for _, b in ipairs(psc.run({ "git", "branch", "-r", "--format=%(refname:lstrip=2)" }) or {}) do
        local n = b:match("^origin/(.+)$") or b
        if n and not n:match("HEAD") then
            psc.add({ name = n, tip = "remote branch" })
        end
    end
end

local function add_prs()
    local data = psc.run({ "gh", "pr", "list", "--json", "number,title", "--limit", "100" }, { format = "json" })
    if data then
        for _, pr in ipairs(data) do
            local num = tostring(pr.number or "")
            if num ~= "" then
                psc.add({ name = num, tip = pr.title or ("PR #" .. num) })
            end
        end
        return
    end
    for _, line in ipairs(psc.run({ "gh", "pr", "list", "--limit", "100" }) or {}) do
        local num = line:match("^%s*(%d+)")
        if num then psc.add({ name = num, tip = line }) end
    end
end

local function add_issues()
    local data = psc.run({ "gh", "issue", "list", "--json", "number,title", "--limit", "100" }, { format = "json" })
    if data then
        for _, iss in ipairs(data) do
            local num = tostring(iss.number or "")
            if num ~= "" then
                psc.add({ name = num, tip = iss.title or ("issue #" .. num) })
            end
        end
        return
    end
    for _, line in ipairs(psc.run({ "gh", "issue", "list", "--limit", "100" }) or {}) do
        local num = line:match("^%s*(%d+)")
        if num then psc.add({ name = num, tip = line }) end
    end
end

local function add_repos()
    local data = psc.run({ "gh", "repo", "list", "--json", "nameWithOwner,description", "--limit", "50" },
        { format = "json" })
    if data then
        for _, r in ipairs(data) do
            if r.nameWithOwner then
                psc.add({ name = r.nameWithOwner, tip = r.description or "" })
            end
        end
        return
    end
    for _, line in ipairs(psc.run({ "gh", "repo", "list", "--limit", "50" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_labels()
    local data = psc.run({ "gh", "label", "list", "--json", "name,description" }, { format = "json" })
    if data then
        for _, l in ipairs(data) do
            if l.name then psc.add({ name = l.name, tip = l.description or "" }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "gh", "label", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_codespaces()
    local data = psc.run({ "gh", "codespace", "list", "--json", "name,displayName,repository" }, { format = "json" })
    if data then
        for _, c in ipairs(data) do
            if c.name then
                local tip = c.displayName or ""
                if c.repository then tip = tip .. " " .. c.repository end
                psc.add({ name = c.name, tip = tip })
            end
        end
    end
end

local function add_extensions()
    for _, line in ipairs(psc.run({ "gh", "extension", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { command = { "pr", "view" } },
    { command = { "pr", "checkout" } },
    { command = { "pr", "checks" } },
    { command = { "pr", "close" } },
    { command = { "pr", "comment" } },
    { command = { "pr", "diff" } },
    { command = { "pr", "edit" } },
    { command = { "pr", "merge" } },
    { command = { "pr", "ready" } },
    { command = { "pr", "reopen" } },
    { command = { "pr", "review" } },
    { command = { "pr", "lock" } },
    { command = { "pr", "unlock" } },
    { command = { "co" } }
}, add_prs)

psc.on({
    { command = { "pr", "view" },          multiple = true },
    { command = { "pr", "checkout" },      multiple = true },
    { command = { "pr", "create" },        option = "--base" },
    { command = { "pr", "create" },        option = "--head" },
    { command = { "issue", "develop" },    option = "--base" },
    { command = { "repo", "sync" },        option = "--branch" },
    { command = { "repo", "view" },        option = "--branch" },
    { command = "browse",                  option = "--branch" },
    { command = { "codespace", "create" }, option = "--branch" },
    { command = { "pr", "create" } },
    { command = { "issue", "develop" } }
}, add_branches)

psc.on({
    { command = { "issue", "view" } },
    { command = { "issue", "close" } },
    { command = { "issue", "comment" } },
    { command = { "issue", "delete" } },
    { command = { "issue", "develop" } },
    { command = { "issue", "edit" } },
    { command = { "issue", "lock" } },
    { command = { "issue", "pin" } },
    { command = { "issue", "reopen" } },
    { command = { "issue", "transfer" } },
    { command = { "issue", "unlock" } },
    { command = { "issue", "unpin" } }
}, add_issues)

psc.on({
    { command = { "repo", "view" } },
    { command = { "repo", "clone" } },
    { command = { "repo", "fork" } },
    { command = { "repo", "delete" } },
    { command = { "repo", "archive" } },
    { command = { "repo", "rename" } },
    { command = { "repo", "edit" } }
}, add_repos)

psc.on({
    { command = { "issue", "create" }, option = "--label" },
    { command = { "pr", "create" },    option = "--label" },
    { command = { "issue", "edit" },   option = "--label" },
    { command = { "pr", "edit" },      option = "--label" }
}, add_labels)

psc.on({
    { command = { "codespace", "view" } },
    { command = { "codespace", "delete" } },
    { command = { "codespace", "edit" } },
    { command = { "codespace", "logs" } },
    { command = { "codespace", "ports" } },
    { command = { "codespace", "rebuild" } },
    { command = { "codespace", "ssh" } },
    { command = { "codespace", "stop" } },
    { command = { "codespace", "code" } },
    { command = { "codespace", "cp" } },
    { command = { "codespace", "jupyter" } },
    { option = "--codespace" }
}, add_codespaces)

psc.on({
    { command = { "extension", "remove" } },
    { command = { "extension", "upgrade" } },
    { command = { "extension", "exec" } }
}, add_extensions)

psc.on({ command = { "cache", "delete" } }, function()
    for _, line in ipairs(psc.run({ "gh", "cache", "list", "--limit", "30" }) or {}) do
        local key = line:match("^(%S+)")
        if key then psc.add({ name = key, tip = line }) end
    end
end)
