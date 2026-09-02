local function add_remotes()
    local lines = psc.run({ "rclone", "listremotes" }) or {}
    for _, l in ipairs(lines) do
        local name = psc.trim(l)
        if name ~= "" then
            psc.add({ name = name, tip = "remote" })
            -- also without trailing colon for convenience
            if name:sub(-1) == ":" then
                psc.add({ name = name:sub(1, -2), tip = "remote (without colon)" })
            end
        end
    end
end

local function add_remote_paths()
    -- if current word looks like remote:path, list that remote
    local cur = psc.typing and psc.typing.input or ""
    local remote = cur:match("^([^:]+):")
    if not remote then
        add_remotes()
        return
    end
    local prefix = remote .. ":"
    -- try lsd for directories, ls for files
    local dirs = psc.run({ "rclone", "lsd", prefix }) or {}
    for _, l in ipairs(dirs) do
        -- lsd output: " -1 2024-01-01 dirName"
        local name = l:match("%s(%S+)%s*$") or l:match("(%S+)$")
        if name then
            psc.add({ name = prefix .. name, tip = l })
        end
    end
    local files = psc.run({ "rclone", "lsf", prefix }) or {}
    for _, l in ipairs(files) do
        local name = psc.trim(l)
        if name ~= "" then
            psc.add({ name = prefix .. name, tip = "path" })
        end
    end
end

local function add_config_names()
    for _, l in ipairs(psc.run({ "rclone", "listremotes", "--long" }) or {}) do
        local name = l:match("^(%S+)")
        if name then psc.add({ name = psc.trim(name, { chars = ":" }), tip = l }) end
    end
end

psc.on({
    { command = "ls",     multiple = true },
    { command = "lsd",    multiple = true },
    { command = "lsf",    multiple = true },
    { command = "lsjson", multiple = true },
    { command = "lsl",    multiple = true },
    { command = "cat",    multiple = true },
    { command = "copy",   multiple = true },
    { command = "copyto", multiple = true },
    { command = "move",   multiple = true },
    { command = "moveto", multiple = true },
    { command = "sync",   multiple = true },
    { command = "check",  multiple = true },
    { command = "delete", multiple = true },
    { command = "purge",  multiple = true },
    { command = "mkdir",  multiple = true },
    { command = "rmdir",  multiple = true },
    { command = "rmdirs", multiple = true },
    { command = "size",   multiple = true },
    { command = "tree",   multiple = true },
    { command = "dedupe", multiple = true },
    { command = "about",  multiple = true }
}, add_remotes)

psc.on({
    { command = { "config", "show" } },
    { command = { "config", "delete" } },
    { command = { "config", "update" } },
    { command = { "config", "edit" } },
    { command = { "config", "dump" } }
}, add_config_names)

psc.on({
    { command = "ls",  multiple = true },
    { command = "lsd", multiple = true },
    { command = "cat", multiple = true }
}, add_remote_paths)
