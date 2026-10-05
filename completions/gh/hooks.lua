local function add_branches()
    local results = psc.run_batch({
        { "git", "branch", "--format=%(refname:lstrip=2)" },
        { "git", "branch", "-r", "--format=%(refname:short)" }
    }) or {}
    for _, b in ipairs(results[1] or {}) do
        if not b:match("^%(.+ detach") then
            psc.add({ name = b, tip = "branch" })
        end
    end
    for _, b in ipairs(results[2] or {}) do
        if not b:match("/HEAD$") then
            psc.add({ name = b, tip = "remote branch" })
        end
    end
end

local function add_prs()
    local data = psc.run({ "gh", "pr", "list", "--json", "number,title", "--limit", "100" },
        { format = "json" }) or {}
    for _, pr in ipairs(data) do
        local num = tostring(pr.number or "")
        if num ~= "" then
            psc.add({ name = num, tip = pr.title or ("PR #" .. num) })
        end
    end
end

local function add_issues()
    local data = psc.run({ "gh", "issue", "list", "--json", "number,title", "--limit", "100" },
        { format = "json" }) or {}
    for _, iss in ipairs(data) do
        local num = tostring(iss.number or "")
        if num ~= "" then
            psc.add({ name = num, tip = iss.title or ("issue #" .. num) })
        end
    end
end

local function add_discussions()
    local data = psc.run({ "gh", "discussion", "list", "--json", "number,title", "--limit", "100" },
        { format = "json" }) or {}
    for _, d in ipairs(data) do
        local num = tostring(d.number or "")
        if num ~= "" then
            psc.add({ name = num, tip = d.title or ("discussion #" .. num) })
        end
    end
end

local function add_repos()
    local data = psc.run({ "gh", "repo", "list", "--json", "nameWithOwner,description", "--limit", "50" },
        { format = "json" }) or {}
    for _, r in ipairs(data) do
        if r.nameWithOwner then
            psc.add({ name = r.nameWithOwner, tip = r.description or "" })
        end
    end
end

local function add_labels()
    local data = psc.run({ "gh", "label", "list", "--json", "name,description" },
        { format = "json" }) or {}
    for _, l in ipairs(data) do
        if l.name then psc.add({ name = l.name, tip = l.description or "" }) end
    end
end

local function add_codespaces()
    local data = psc.run({ "gh", "codespace", "list", "--json", "name,displayName,repository" },
        { format = "json" }) or {}
    for _, c in ipairs(data) do
        if c.name then
            local tip = c.displayName or ""
            if c.repository then tip = tip .. " " .. c.repository end
            psc.add({ name = c.name, tip = tip })
        end
    end
end

local function add_extensions()
    for _, line in ipairs(psc.run({ "gh", "extension", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_releases()
    local data = psc.run({ "gh", "release", "list", "--json", "tagName,name,isDraft,isPrerelease", "--limit", "50" },
        { format = "json" }) or {}
    for _, r in ipairs(data) do
        if r.tagName then
            local tip = r.name or r.tagName
            if r.isDraft then tip = tip .. " (draft)" end
            if r.isPrerelease then tip = tip .. " (prerelease)" end
            psc.add({ name = r.tagName, tip = tip })
        end
    end
end

-- `run watch` requires the id, so a slot left empty there is unusable, not just
-- unhelpful.
local function add_runs()
    local data = psc.run({ "gh", "run", "list", "--json", "databaseId,displayTitle,workflowName,status", "--limit", "50" },
        { format = "json" }) or {}
    for _, r in ipairs(data) do
        local id = tostring(r.databaseId or "")
        if id ~= "" then
            local tip = r.displayTitle or ""
            if r.workflowName then tip = r.workflowName .. " --- " .. tip end
            if r.status then tip = tip .. " (" .. r.status .. ")" end
            psc.add({ name = id, tip = tip })
        end
    end
end

local function add_workflows()
    local data = psc.run({ "gh", "workflow", "list", "--json", "name,path,state", "--limit", "100" },
        { format = "json" }) or {}
    for _, w in ipairs(data) do
        if w.name then
            local tip = w.path or ""
            if w.state then tip = tip .. " (" .. w.state .. ")" end
            psc.add({ name = w.name, tip = tip })
        end
    end
end

local function add_gists()
    local data = psc.run({ "gh", "gist", "list", "--json", "id,description", "--limit", "50" },
        { format = "json" }) or {}
    for _, g in ipairs(data) do
        if g.id then psc.add({ name = g.id, tip = g.description or "" }) end
    end
end

-- `gh project list --format json` because the project commands predate `--json`.
local function add_projects()
    local data = psc.run({ "gh", "project", "list", "--format", "json", "--limit", "100" },
        { format = "json" }) or {}
    for _, p in ipairs(data) do
        local num = tostring(p.number or "")
        if num ~= "" then
            psc.add({ name = num, tip = p.title or ("project " .. num) })
        end
    end
end

local function add_secrets()
    for _, line in ipairs(psc.run({ "gh", "secret", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_variables()
    for _, line in ipairs(psc.run({ "gh", "variable", "list" }) or {}) do
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
    { command = { "pr", "revert" } },
    { command = { "pr", "update-branch" } },
    { command = "co" }
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
    { command = { "discussion", "view" } },
    { command = { "discussion", "comment" } },
    { command = { "discussion", "edit" } }
}, add_discussions)

psc.on({
    { command = { "repo", "view" } },
    { command = { "repo", "clone" } },
    { command = { "repo", "fork" } },
    { command = { "repo", "delete" } },
    { command = { "repo", "archive" } },
    { command = { "repo", "rename" } },
    { command = { "repo", "edit" } },
    { command = { "repo", "sync" } },
    { command = { "repo", "set-default" } },
    { command = { "repo", "unarchive" } }
}, add_repos)

psc.on({
    { command = { "issue", "create" }, option = "--label" },
    { command = { "pr", "create" },    option = "--label" },
    { command = { "issue", "edit" },   option = "--add-label" },
    { command = { "issue", "edit" },   option = "--remove-label" },
    { command = { "pr", "edit" },      option = "--add-label" },
    { command = { "pr", "edit" },      option = "--remove-label" },
    { command = { "label", "edit" } },
    { command = { "label", "delete" } }
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
    { command = { "extensions", "remove" } },
    { command = { "extensions", "upgrade" } },
    { command = { "extensions", "exec" } }
}, add_extensions)

psc.on({ command = { "cache", "delete" } }, function()
    for _, line in ipairs(psc.run({ "gh", "cache", "list", "--limit", "30" }) or {}) do
        local key = line:match("^(%S+)")
        if key then psc.add({ name = key, tip = line }) end
    end
end)

psc.on({
    { command = { "release", "view" } },
    { command = { "release", "edit" } },
    { command = { "release", "delete" } },
    { command = { "release", "download" } },
    { command = { "release", "upload" } },
    { command = { "release", "verify" } },
    { command = { "release", "verify-asset" } },
    { command = { "release", "delete-asset" } }
}, add_releases)

psc.on({
    { command = { "run", "view" } },
    { command = { "run", "watch" } },
    { command = { "run", "cancel" } },
    { command = { "run", "delete" } },
    { command = { "run", "rerun" } },
    { command = { "run", "download" } }
}, add_runs)

psc.on({
    { command = { "workflow", "view" } },
    { command = { "workflow", "run" } },
    { command = { "workflow", "disable" } },
    { command = { "workflow", "enable" } }
}, add_workflows)

psc.on({
    { command = { "gist", "view" } },
    { command = { "gist", "edit" } },
    { command = { "gist", "delete" } },
    { command = { "gist", "rename" } }
}, add_gists)

psc.on({
    { command = { "project", "view" } },
    { command = { "project", "close" } },
    { command = { "project", "copy" } },
    { command = { "project", "delete" } },
    { command = { "project", "edit" } },
    { command = { "project", "link" } },
    { command = { "project", "unlink" } },
    { command = { "project", "mark-template" } },
    { command = { "project", "field-create" } },
    { command = { "project", "field-list" } },
    { command = { "project", "item-add" } },
    { command = { "project", "item-archive" } },
    { command = { "project", "item-create" } },
    { command = { "project", "item-delete" } },
    { command = { "project", "item-edit" } },
    { command = { "project", "item-list" } }
}, add_projects)

psc.on({
    { command = { "secret", "set" } },
    { command = { "secret", "delete" } }
}, add_secrets)

psc.on({
    { command = { "variable", "set" } },
    { command = { "variable", "get" } }
}, add_variables)
