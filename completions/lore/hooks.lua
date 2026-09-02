local function add_branches()
    local lines = psc.run({ "lore", "branch", "list" })
    if not lines then return end
    for _, line in ipairs(lines) do
        local name = psc.trim(line)
        -- branch list may be "branch  id  status"
        local first = name:match("^(%S+)")
        if first and first ~= "Branch" and first ~= "branch" and not first:match("^%-") then
            psc.add({ name = first, tip = name })
        end
    end
end

local function add_revisions()
    local lines = psc.run({ "lore", "history" })
    if lines then
        for _, line in ipairs(lines) do
            local rev = line:match("^(%x%x%x%x+)")
            if rev then psc.add({ name = rev, tip = psc.trim(line) }) end
        end
        return
    end
    lines = psc.run({ "lore", "revision", "list" })
    if not lines then return end
    for _, line in ipairs(lines) do
        local rev = line:match("^(%S+)")
        if rev then psc.add({ name = rev, tip = psc.trim(line) }) end
    end
end

local function add_files()
    local lines = psc.run({ "lore", "status" })
    if lines then
        for _, line in ipairs(lines) do
            local f = line:match("^..%s+(.+)$") or psc.trim(line)
            if f and f ~= "" then psc.add({ name = f, tip = line }) end
        end
    end
    -- fallback to ls
    local entries = psc.ls(".")
    if entries then
        for _, e in ipairs(entries) do
            if not e.is_dir then psc.add({ name = e.name, tip = e.path }) end
        end
    end
end

local function add_remotes()
    local lines = psc.run({ "lore", "repository", "list" })
    if not lines then return end
    for _, line in ipairs(lines) do
        local n = line:match("^(%S+)")
        if n then psc.add({ name = n, tip = psc.trim(line) }) end
    end
end

psc.on({
    { command = { "branch", "archive" } },
    { command = { "branch", "info" } },
    { command = { "branch", "diff" } },
    { command = { "branch", "merge" } },
    { command = { "branch", "create" } },
    { command = { "branch", "list" } }
}, add_branches)

psc.on({
    { command = "history" },
    { command = "diff" },
    { command = { "file", "history" } },
    { command = { "file", "diff" } }
}, add_revisions)

psc.on({
    { command = "status" },
    { command = { "file", "info" } },
    { command = { "file", "diff" } },
    { command = "stage" },
    { command = "unstage" },
    { command = "reset" },
    { command = "dirty" }
}, add_files)

psc.on({ command = { "repository", "list" } }, add_remotes)
