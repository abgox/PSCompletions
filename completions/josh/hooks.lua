local function option_value(name)
    for index, token in ipairs(psc.tokens) do
        if token.type == "option" and psc.eq(token.name, name) then
            local value = psc.tokens[index + 1]
            if value and value.type == "value" then
                return value.input
            end
        end
    end
end

local function add_branch()
    psc.add(psc.items(psc.run({ "git", "for-each-ref", "--format=%(refname:short)", "refs/heads" }) or {}))
end

local function add_ref()
    psc.add({ name = "HEAD" })
    for _, ref in ipairs(psc.run({ "git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/tags", "refs/remotes" }) or {}) do
        -- origin/HEAD duplicates the local HEAD row.
        if not ref:match("/HEAD$") then
            psc.add({ name = ref })
        end
    end
end

local function add_revision()
    psc.add({ name = ".", tip = { ["en-US"] = "working tree", ["zh-CN"] = "工作树" } })
    psc.add({ name = "+", tip = { ["en-US"] = "index", ["zh-CN"] = "索引" } })
    add_ref()
end

local function add_remote()
    psc.add(psc.items(psc.run({ "git", "remote" }) or {}))
end

local function add_change()
    local argv = { "josh", "changes", "list" }
    -- Reuse an already-typed scope so the ids come from the same branch or remote.
    local branch = option_value("--branch")
    local remote = option_value("--remote")
    if branch then
        argv[#argv + 1] = "--branch"
        argv[#argv + 1] = branch
    end
    if remote then
        argv[#argv + 1] = "--remote"
        argv[#argv + 1] = remote
    end
    for _, line in ipairs(psc.run(argv) or {}) do
        local id = line:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]%s+(%S+)%s+D=")
        if id and id ~= "<no-change-id>" then
            psc.add({ name = id, tip = line:match("M=%S+%s+(.+)$") })
        end
    end
end

local function add_link()
    -- josh gates the whole link lifecycle behind JOSH_EXPERIMENTAL_FEATURES.
    for _, line in ipairs(psc.run({ "josh", "link", "list" }, { env = { JOSH_EXPERIMENTAL_FEATURES = "1" } }) or {}) do
        local id = line:match("^([^\t]+)\t")
        if id then
            psc.add({ name = id })
        end
    end
end

psc.on({
    { command = { "changes", "list" }, option = "--branch" },
    { command = { "changes", "show" }, option = "--branch" },
    { command = { "changes", "deps" }, option = "--branch" },
    { command = { "changes", "comment" }, option = "--branch" },
    { command = { "changes", "sync" }, option = "--branch" },
    { command = "push", option = "--base" },
    { command = { "changes", "publish" }, option = "--base" }
}, add_branch)

psc.on({
    { command = "fetch", option = "--ref" },
    { command = { "changes", "pull" }, option = "--ref" },
    { command = { "changes", "comment" } }
}, add_ref)

psc.on({
    { command = { "compose", "run" }, option = "--revision" },
    { command = { "compose", "shell" }, option = "--revision" },
    { command = { "compose", "graph" }, option = "--revision" },
    { command = { "compose", "list-images" }, option = "--revision" },
    { command = { "compose", "list-jobs" }, option = "--revision" }
}, add_revision)

psc.on({
    { command = "fetch", option = "--remote" },
    { command = { "changes", "pull" }, option = "--remote" },
    { command = { "changes", "list" }, option = "--remote" },
    { command = { "changes", "show" }, option = "--remote" },
    { command = { "changes", "deps" }, option = "--remote" },
    { command = { "changes", "comment" }, option = "--remote" },
    { command = { "changes", "sync" }, option = "--remote" },
    { command = { "compose", "pull" }, option = "--remote" },
    { command = { "compose", "push" }, option = "--remote" },
    { command = "push" },
    { command = { "changes", "publish" } },
    { command = "filter" },
    { command = { "cache", "build" } },
    { command = { "cache", "fetch" } },
    { command = { "cache", "push" } }
}, add_remote)

psc.on({
    { command = { "changes", "show" } },
    { command = { "changes", "deps" } },
    { command = { "changes", "comment" } }
}, add_change)

psc.on({ command = { "link", "rm" } }, add_link)

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
