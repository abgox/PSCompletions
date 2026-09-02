local function add_branches()
    for _, b in ipairs(psc.run({ "git", "branch", "--format=%(refname:lstrip=2)" }) or {}) do
        if not b:match("^%(.+ detach") then
            psc.add({ name = b, tip = "branch" })
        end
    end
end

local function add_mrs()
    -- try json output then fallback to plain
    local data = psc.run({ "glab", "mr", "list", "--output", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, mr in ipairs(data) do
            local id = tostring(mr.iid or mr.id or mr.number or "")
            if id ~= "" then
                psc.add({ name = id, tip = mr.title or mr.description or "" })
            end
        end
        if #data > 0 then return end
    end
    local data2 = psc.run({ "glab", "mr", "list" }) or {}
    for _, line in ipairs(data2) do
        local num = line:match("#(%d+)") or line:match("^%s*(%d+)")
        if num then psc.add({ name = num, tip = line }) end
    end
end

local function add_issues()
    local data = psc.run({ "glab", "issue", "list", "--output", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, iss in ipairs(data) do
            local id = tostring(iss.iid or iss.id or iss.number or "")
            if id ~= "" then
                psc.add({ name = id, tip = iss.title or "" })
            end
        end
        if #data > 0 then return end
    end
    for _, line in ipairs(psc.run({ "glab", "issue", "list" }) or {}) do
        local num = line:match("#(%d+)") or line:match("^%s*(%d+)")
        if num then psc.add({ name = num, tip = line }) end
    end
end

local function add_labels()
    local data = psc.run({ "glab", "label", "list", "--output", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, l in ipairs(data) do
            local name = l.name or l.title
            if name then psc.add({ name = name, tip = l.description or l.color or "" }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "glab", "label", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_repos()
    local data = psc.run({ "glab", "repo", "list", "--output", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, r in ipairs(data) do
            local name = r.path_with_namespace or r.name or r.nameWithOwner
            if name then psc.add({ name = name, tip = r.description or "" }) end
        end
        return
    end
    for _, line in ipairs(psc.run({ "glab", "repo", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

local function add_pipelines()
    for _, line in ipairs(psc.run({ "glab", "ci", "list" }) or {}) do
        local id = line:match("^%s*(%d+)")
        if id then psc.add({ name = id, tip = line }) end
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

psc.on({ command = { "ci", "view" } }, add_branches)

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
