local function add_bookmark()
    psc.add(
        psc.items(
            psc.run({
                "jj", "bookmark", "list", "--all-remotes", "--template",
                'if(remote, label("bookmark", name ++ "@" ++ remote), label("bookmark", name)) ++ "\n"' }) or {},
            function(name)
                return { name = name, tip = "bookmark --- " .. name }
            end
        )
    )
end

local function add_tag()
    psc.add(psc.items(psc.run({ "jj", "tag", "list", "--template", 'name ++ "\\n"' }) or {}, function(name)
        return { name = name, tip = "tag --- " .. name }
    end))
end

local function add_common_revsets()
    psc.add(psc.mount_items({ "next", "abandon", "next" }))
end

local function add_revsets()
    for _, line in ipairs(psc.run({
        "jj", "log",
        "-r", "present(@) | present(trunk()) | ancestors(immutable_heads().., 2)",
        "-T", 'change_id.short() ++ ": " ++ description.first_line() ++ "\\n"',
        "--no-pager", "--no-graph", "--limit", "30"
    }) or {}) do
        local part0, part1 = line:match("^([^:]+):%s*(.*)$")
        if part0 then
            local tip = part1
            if tip == nil or tip == "" then
                tip = "(no description set)"
            end
            psc.add({ name = part0, tip = tip })
        end
    end
end

local function add_remote()
    for _, line in ipairs(psc.run({ "jj", "git", "remote", "list" }) or {}) do
        local name, url = line:match("^(%S+)%s+(.*)$")
        if name then
            psc.add({ name = name, tip = url })
        end
    end
end

local function add_operation()
    for _, line in ipairs(psc.run({
        "jj", "operation", "log", "--no-graph", "--limit", "20",
        "-T", 'id.short() ++ " " ++ description.first_line() ++ "\\n"'
    }) or {}) do
        local id = line:match("^(%S+)")
        if id then
            psc.add({ name = id, tip = line })
        end
    end
end

local function add_files()
    psc.add(psc.items(psc.run({ "jj", "file", "list" }) or {}, function(name)
        return { name = name, tip = "file --- " .. name }
    end))
end

local function add_workspaces()
    for _, line in ipairs(psc.run({ "jj", "workspace", "list" }) or {}) do
        local name, rest = line:match("^(.-):%s*(.-)%s*$")
        if name then
            if rest == "" then rest = nil end
            psc.add({ name = name, tip = rest })
        end
    end
end

local function add_config_keys()
    psc.add(psc.items(
        psc.run({ "jj", "config", "list", "--include-defaults", "--template", 'name ++ "\n"' }) or {},
        function(name)
            return { name = name, tip = "config key --- " .. name }
        end
    ))
end

-- abandon already lists the home statically; mounting there would inject it twice
psc.on({
    { command = "describe",      multiple = true },
    { command = "duplicate",     multiple = true },
    { command = "edit",          multiple = true },
    { command = "metaedit",      multiple = true },
    { command = "new",           multiple = true },
    { command = "arrange",       multiple = true },
    { command = "parallelize",   multiple = true },
    { command = "show",          multiple = true },
    { option = "--revisions" },
    { option = "--revision" },
    { option = "-r" },
    { option = "--range" },
    { option = "--onto" },
    { option = "--destination" },
    { option = "--insert-after" },
    { option = "--insert-before" },
    { option = "--from" },
    { option = "--to" },
    { option = "--into" },
    { option = "--change" },
    { option = "--source" },
    { option = "--changes-in" },
    { option = "--show-changes-in" }
}, add_common_revsets)

psc.on({
    { command = "abandon",       multiple = true },
    { command = "describe",      multiple = true },
    { command = "duplicate",     multiple = true },
    { command = "edit",          multiple = true },
    { command = "metaedit",      multiple = true },
    { command = "new",           multiple = true },
    { command = "arrange",       multiple = true },
    { command = "parallelize",   multiple = true },
    { command = "show",          multiple = true },
    { option = "--revisions" },
    { option = "--revision" },
    { option = "-r" },
    { option = "--range" },
    { option = "--onto" },
    { option = "--destination" },
    { option = "--insert-after" },
    { option = "--insert-before" },
    { option = "--from" },
    { option = "--to" },
    { option = "--into" },
    { option = "--change" },
    { option = "--source" },
    { option = "--changes-in" },
    { option = "--show-changes-in" }
}, add_revsets)

psc.on({
    { command = { "tag", "delete" },  multiple = true },
    { command = { "tag", "set" },     multiple = true },
    { command = { "tag", "track" },   multiple = true },
    { command = { "tag", "untrack" }, multiple = true },
    { command = { "tag", "list" },    multiple = true },
    { command = { "git", "push" }, option = "--tag" }
}, add_tag)

psc.on({
    { command = "abandon",       multiple = true },
    { command = "describe",      multiple = true },
    { command = "duplicate",     multiple = true },
    { command = "edit",          multiple = true },
    { command = "metaedit",      multiple = true },
    { command = "new",           multiple = true },
    { command = "arrange",       multiple = true },
    { command = "parallelize",   multiple = true },
    { command = "show",          multiple = true },
    { command = { "bookmark", "set" },     multiple = true },
    { command = { "bookmark", "move" },    multiple = true },
    { command = { "bookmark", "forget" },  multiple = true },
    { command = { "bookmark", "delete" },  multiple = true },
    { command = { "bookmark", "track" },   multiple = true },
    { command = { "bookmark", "untrack" }, multiple = true },
    { command = { "bookmark", "advance" }, multiple = true },
    { command = { "bookmark", "list" },    multiple = true },
    { command = { "bookmark", "rename" } },
    { option = "--bookmark" }
}, add_bookmark)

psc.on({
    { command = { "git", "remote", "remove" } },
    { command = { "git", "remote", "rename" } },
    { command = { "git", "remote", "set-url" } },
    { option = "--remote" }
}, add_remote)

psc.on({
    { command = { "operation", "restore" },   multiple = true },
    { command = { "operation", "revert" },    multiple = true },
    { command = { "operation", "show" },      multiple = true },
    { command = { "operation", "abandon" },   multiple = true },
    { command = { "operation", "integrate" } },
    { option = "--operation" },
    { option = "--at-operation" }
}, add_operation)

psc.on({
    { command = { "config", "get" } },
    { command = { "config", "set" } },
    { command = { "config", "unset" } }
}, add_config_keys)

psc.on({
    { command = { "file", "annotate" } },
    { command = { "file", "show" },    multiple = true },
    { command = { "file", "chmod" },   multiple = true },
    { command = { "file", "delete" },  multiple = true },
    { command = { "file", "untrack" }, multiple = true },
    { command = { "file", "edit" } }
}, add_files)

psc.on({
    { command = { "workspace", "remove" }, multiple = true },
    { command = { "workspace", "forget" }, multiple = true }
}, add_workspaces)
