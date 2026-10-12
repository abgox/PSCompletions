local function add_branches()
    for _, b in ipairs(psc.run({ "git", "branch", "--format=%(refname:lstrip=2)" }) or {}) do
        if not b:match("^%(.+ detach") then
            psc.add({ name = b, tip = "branch" })
        end
    end
end

local function add_mrs()
    for _, mr in ipairs(psc.run({ "glab", "mr", "list", "--output", "json" }, { format = "json" }) or {}) do
        local id = tostring(mr.iid or "")
        if id ~= "" then psc.add({ name = id, tip = mr.title or "" }) end
    end
end

local function add_issues()
    for _, iss in ipairs(psc.run({ "glab", "issue", "list", "--output", "json" }, { format = "json" }) or {}) do
        local id = tostring(iss.iid or "")
        if id ~= "" then psc.add({ name = id, tip = iss.title or "" }) end
    end
end

local function add_labels()
    for _, l in ipairs(psc.run({ "glab", "label", "list", "--output", "json" }, { format = "json" }) or {}) do
        if l.name then psc.add({ name = l.name, tip = l.description or "" }) end
    end
end

local function add_repos()
    for _, r in ipairs(psc.run({ "glab", "repo", "list", "--output", "json" }, { format = "json" }) or {}) do
        local name = r.path_with_namespace or r.name
        if name then psc.add({ name = name, tip = r.description or "" }) end
    end
end

local function add_pipelines()
    for _, p in ipairs(psc.run({ "glab", "ci", "list", "--output", "json" }, { format = "json" }) or {}) do
        local id = tostring(p.id or "")
        if id ~= "" then psc.add({ name = id, tip = p.status or "" }) end
    end
end

psc.on({
    { command = { "mr", "view" } },
    { command = { "mr", "checkout" } },
    { command = { "mr", "approve" } },
    { command = { "mr", "approvers" } },
    { command = { "mr", "close" } },
    { command = { "mr", "merge" } },
    { command = { "mr", "rebase" } },
    { command = { "mr", "note" } },
    { command = { "mr", "diff" } },
    { command = { "mr", "update" } },
    { command = { "mr", "reopen" } },
    { command = { "mr", "revoke" } },
    { command = { "mr", "subscribe" } },
    { command = { "mr", "unsubscribe" } },
    { command = { "mr", "todo" } },
    { command = { "mr", "delete" } },
    { command = { "mr", "issues" } }
}, add_mrs)

-- every one of those slots is "[<id> | <branch>]", so a branch is equally valid there
psc.on({
    { command = { "mr", "view" } },
    { command = { "mr", "checkout" } },
    { command = { "mr", "approve" } },
    { command = { "mr", "approvers" } },
    { command = { "mr", "close" } },
    { command = { "mr", "merge" } },
    { command = { "mr", "rebase" } },
    { command = { "mr", "note" } },
    { command = { "mr", "diff" } },
    { command = { "mr", "update" } },
    { command = { "mr", "reopen" } },
    { command = { "mr", "revoke" } },
    { command = { "mr", "subscribe" } },
    { command = { "mr", "unsubscribe" } },
    { command = { "mr", "todo" } },
    { command = { "mr", "delete" } },
    { command = { "mr", "issues" } },
    { command = { "ci", "view" } }
}, add_branches)

psc.on({
    { command = { "issue", "view" } },
    { command = { "issue", "close" } },
    { command = { "issue", "reopen" } },
    { command = { "issue", "delete" } },
    { command = { "issue", "update" } },
    { command = { "issue", "note" } },
    { command = { "issue", "subscribe" } },
    { command = { "issue", "unsubscribe" } }
}, add_issues)

psc.on({
    { command = { "label", "get" } },
    { command = { "label", "delete" } }
}, add_labels)

psc.on({
    { command = { "repo", "view" } },
    { command = { "repo", "clone" } },
    { command = { "repo", "fork" } },
    { command = { "repo", "delete" } },
    { command = { "repo", "archive" } }
}, add_repos)

psc.on({
    { command = { "ci", "view" } },
    { command = { "ci", "cancel" } },
    { command = { "ci", "retry" } },
    { command = { "ci", "delete" } }
}, add_pipelines)
