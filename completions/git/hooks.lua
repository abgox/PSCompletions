local function add_branch()
    for _, b in ipairs(psc.run({ "git", "branch", "--format=%(refname:lstrip=2)" }) or {}) do
        -- Detached HEAD shows up as a "(HEAD detached ...)" pseudo-ref.
        if not b:match("^%(.+ detach") then
            psc.add({ name = b, tip = "branch --- " .. b })
        end
    end
end

local function add_head()
    local heads = { "HEAD", "FETCH_HEAD", "ORIG_HEAD", "MERGE_HEAD" }
    local cmds = {}
    for _, h in ipairs(heads) do
        table.insert(cmds, { "git", "show", h, "--relative-date", "-q" })
    end
    local results = psc.run_batch(cmds) or {}
    for i, h in ipairs(heads) do
        local lines = results[i]
        if lines then
            psc.add({ name = h, tip = psc.join(lines, "\n") })
        end
    end
end

local function add_commit()
    local max = psc.config.max_commit
    local sep = "PSCOMPLETIONS_COMMIT_SEP"
    local args = { "git", "log", "--pretty=format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n" .. sep }
    if max ~= -1 then
        table.insert(args, "-n")
        table.insert(args, tostring(max))
    end
    local lines = psc.run(args) or {}
    local buf = {}
    for _, l in ipairs(lines) do
        if l == sep then
            -- Empty-message commits (initial, --allow-empty-message) are still valid refs.
            -- Only their tooltip loses the message part.
            if #buf >= 1 then
                local tip_parts = {}
                if buf[2] then table.insert(tip_parts, buf[2]) end
                if buf[3] then table.insert(tip_parts, buf[3]) end
                local msg = {}
                for i = 4, #buf do
                    table.insert(msg, buf[i])
                end
                if #msg > 0 then
                    table.insert(tip_parts, psc.join(msg, "\n"))
                end
                psc.add({ name = buf[1], tip = psc.join(tip_parts, "\n") })
            end
            buf = {}
        else
            table.insert(buf, l)
        end
    end
end

local function add_tag()
    psc.add(psc.items(psc.run({ "git", "tag", "-l" }) or {}, function(name)
        return { name = name, tip = "tag --- " .. name }
    end))
end

-- Stash entries are addressed by their numeric index (e.g. `git stash apply 0`).
local function add_stash()
    for _, line in ipairs(psc.run({ "git", "stash", "list" }) or {}) do
        local id = line:match("stash@{(%d+)}")
        if id then
            psc.add({ name = id, tip = line })
        end
    end
end

local function add_remote()
    psc.add(psc.items(psc.run({ "git", "remote" }) or {}, function(name)
        return { name = name, tip = "remote --- " .. name }
    end))
end

-- Porcelain status lines are "XY <path>" (X=index, Y=worktree). Cover modified /
-- added / deleted / renamed / copied and conflict shapes (UU/AA/AU/UA/DU/UD/DD);
-- renames and copies print "old -> new", so complete the new path.
local function add_modified_files()
    for _, line in ipairs(psc.run({ "git", "status", "--porcelain" }) or {}) do
        local code, f = line:sub(1, 2), line:sub(4)
        if #f > 0 and (code == "??" or code:match("[MDARCU]")) then
            local new_path = f:match("^.+ %-> (.+)$")
            if new_path then
                f = new_path
            end
            psc.add({ name = f, tip = line })
        end
    end
end

local function add_tracked_files()
    psc.add(psc.items(psc.run({ "git", "ls-files" }) or {}, function(name)
        return { name = name, tip = "tracked --- " .. name }
    end))
end

local function add_conflicts()
    for _, f in ipairs(psc.run({ "git", "diff", "--name-only", "--diff-filter=U" }) or {}) do
        psc.add({ name = f, tip = "conflict --- " .. f })
    end
end

psc.on({
    { command = "merge" },
    { command = "branch" },
    { command = "switch" },
    { command = "checkout" },
    { command = "rebase" },
    { command = "cherry-pick" },
    { command = "cherry" },
    { command = "log" },
    { command = "describe" },
    { command = "shortlog" },
    { command = "show-branch" },
    { command = "merge-base" },
    { command = "format-patch" },
    { command = "archive" },
    { command = { "bisect", "start" }, multiple = true },
    { command = "switch",              option = "--create" },
    { command = "switch",              option = "--force-create" },
    { command = "switch",              option = "--orphan" },
    { command = "checkout",            option = "--orphan" },
    { command = "checkout",            option = "-b" },
    { command = "branch",              option = "--move" },
    { command = "branch",              option = "-M" },
    { command = "branch",              option = "--copy" },
    { command = "branch",              option = "-C" },
    { command = "branch",              option = "-d" },
    { command = "branch",              option = "--set-upstream-to" },
    { command = "branch",              option = "--points-at" },
    { command = "tag",                 option = "--points-at" },
    { command = "rebase",              option = "--onto" },
    { command = "restore",             option = "--source" },
    { command = "fetch",               option = "--shallow-exclude" }
}, add_branch)

psc.on({
    { command = "merge" },
    { command = "rebase" },
    { command = "checkout" },
    { command = "cherry-pick" },
    { command = "cherry" },
    { command = "log" },
    { command = "describe" },
    { command = "shortlog" },
    { command = "show-branch" },
    { command = "merge-base" },
    { command = "format-patch" },
    { command = "range-diff" },
    { command = "reset" },
    { command = "show" },
    { command = { "bisect", "start" }, multiple = true },
    { command = "rebase",              option = "--onto" },
    { command = "branch",              option = "--points-at" },
    { command = "tag",                 option = "--points-at" }
}, add_head)

psc.on({
    { command = "commit" },
    { command = "rebase" },
    { command = "checkout" },
    { command = "cherry-pick" },
    { command = "cherry" },
    { command = "log" },
    { command = "describe" },
    { command = "shortlog" },
    { command = "show-branch" },
    { command = "merge-base" },
    { command = "format-patch" },
    { command = "range-diff" },
    { command = "reset" },
    { command = "show" },
    { command = "diff" },
    { command = "archive" },
    { command = "revert" },
    { command = "verify-commit" },
    { command = { "bisect", "start" }, multiple = true },
    { command = "rebase",              option = "--onto" },
    { command = "restore",             option = "--source" },
    { command = "branch",              option = "--contains" },
    { command = "branch",              option = "--merged" },
    { command = "branch",              option = "--no-merged" },
    { command = "branch",              option = "--points-at" },
    { command = "tag",                 option = "--contains" },
    { command = "tag",                 option = "--merged" },
    { command = "tag",                 option = "--no-merged" },
    { command = "tag",                 option = "--points-at" },
    { command = "commit",              option = "--squash" },
    { command = "commit",              option = "--reedit-message" }
}, add_commit)

psc.on({
    { command = "tag" },
    { command = "verify-tag" },
    { command = "archive" },
    { command = "tag",       option = "--delete" },
    { command = "tag",       option = "--verify" },
    { command = "tag",       option = "--points-at" },
    { command = "branch",    option = "--points-at" },
    { command = "fetch",     option = "--shallow-exclude" }
}, add_tag)

psc.on({
    { command = { "stash", "show" } },
    { command = { "stash", "pop" } },
    { command = { "stash", "apply" } },
    { command = { "stash", "drop" } },
    { command = { "stash", "branch" } }
}, add_stash)

psc.on({
    { command = "push" },
    { command = "pull" },
    { command = "fetch" },
    { command = "ls-remote" },
    { command = { "remote", "rename" } },
    { command = { "remote", "remove" } },
    { command = { "remote", "set-url" } },
    { command = { "remote", "get-url" } },
    { command = { "remote", "prune" } },
    { command = { "remote", "set-head" } },
    { command = { "remote", "set-branches" } },
    { command = { "lfs", "fetch" } },
    { command = { "lfs", "pull" } },
    { command = { "lfs", "push" } }
}, add_remote)

psc.on({
    { command = "add",              multiple = true },
    { command = "clean" },
    { command = "restore" },
    { command = "difftool" },
    { command = "diff" },
    { command = { "stash", "push" } }
}, add_modified_files)

psc.on({
    { command = "rm" },
    { command = "mv" },
    { command = "ls-files" },
    { command = "blame" },
    { command = "annotate" }
}, add_tracked_files)

psc.on({ command = "mergetool" }, add_conflicts)

psc.on({
    { command = { "config", "unset" } },
    { command = { "config", "get" } }
}, function()
    psc.add(psc.mount_items({ "next", "config", "set", "next" }))
end)
