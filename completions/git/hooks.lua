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

-- Only offered where a remote branch is what the user is actually reaching for.
-- `%(symref)` is empty for a real ref, which drops the origin/HEAD pseudo-ref.
local function add_remote_branch()
    for _, line in ipairs(psc.run({ "git", "for-each-ref", "--format=%(refname:short)|%(symref)", "refs/remotes" }) or {}) do
        local name, symref = line:match("^([^|]*)|(.*)$")
        if name and name ~= "" and symref == "" then
            psc.add({ name = name, tip = "remote branch --- " .. name })
        end
    end
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

local function load_aliases()
    local aliases = {}
    -- --get-regexp prints "alias.<name> <expansion>"; no match at all exits non-zero (nil).
    for _, line in ipairs(psc.run({ "git", "config", "--get-regexp", "^alias[.]" }) or {}) do
        local name, expansion = line:match("^alias%.(%S+)%s+(.*)$")
        if name then
            table.insert(aliases, { name = name, expansion = expansion })
        end
    end
    return aliases
end

local function add_alias_keys()
    psc.add(psc.items(load_aliases(), function(a)
        return { name = "alias." .. a.name, tip = "alias --- " .. a.expansion }
    end))
end

local function add_aliases()
    psc.add(psc.items(load_aliases(), function(a)
        return { name = a.name, tip = "alias --- " .. a.expansion }
    end))
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
    { command = "branch",              option = "--set-upstream-to" },
    { command = "branch",              option = "--points-at" },
    { command = "tag",                 option = "--points-at" },
    { command = "rebase",              option = "--onto" },
    { command = "restore",             option = "--source" },
    { command = "merge-tree" },
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
    { command = "commit",              option = "--reedit-message" },
    { command = "annotate" },
    { command = "annotate", option = "--ignore-rev" },
    { command = "branch", option = "--forked" },
    { command = "branch", option = "--no-contains" },
    { command = "check-attr", option = "--source" },
    { command = "commit", option = "--fixup" },
    { command = "commit", option = "--reuse-message" },
    { command = "fetch", option = "--negotiation-include" },
    { command = "fetch", option = "--negotiation-restrict" },
    { command = "fetch", option = "--negotiation-tip" },
    { command = "for-each-ref", option = "--points-at" },
    { command = "format-patch", option = "--base" },
    { command = { "history", "drop" } },
    { command = { "history", "fixup" } },
    { command = { "history", "reword" } },
    { command = { "history", "split" } },
    { command = "log", option = "--ancestry-path" },
    { command = "log", option = "--find-object" },
    { command = "ls-files", option = "--with-tree" },
    { command = "merge-tree", option = "--merge-base" },
    { command = "notes" },
    { command = "notes", option = "--reedit-message" },
    { command = "notes", option = "--reuse-message" },
    { command = "pickaxe", option = "--ignore-rev" },
    { command = "pull", option = "--negotiation-include" },
    { command = "pull", option = "--negotiation-restrict" },
    { command = "pull", option = "--negotiation-tip" },
    { command = "refs", option = "--contains" },
    { command = "refs", option = "--merged" },
    { command = "refs", option = "--no-contains" },
    { command = "refs", option = "--no-merged" },
    { command = "refs", option = "--points-at" },
    { command = { "refs", "create" }, option = "--contains" },
    { command = { "refs", "create" }, option = "--merged" },
    { command = { "refs", "create" }, option = "--no-contains" },
    { command = { "refs", "create" }, option = "--no-merged" },
    { command = { "refs", "create" }, option = "--points-at" },
    { command = { "refs", "delete" }, option = "--contains" },
    { command = { "refs", "delete" }, option = "--merged" },
    { command = { "refs", "delete" }, option = "--no-contains" },
    { command = { "refs", "delete" }, option = "--no-merged" },
    { command = { "refs", "delete" }, option = "--points-at" },
    { command = { "refs", "list" }, option = "--contains" },
    { command = { "refs", "list" }, option = "--merged" },
    { command = { "refs", "list" }, option = "--no-contains" },
    { command = { "refs", "list" }, option = "--no-merged" },
    { command = { "refs", "list" }, option = "--points-at" },
    { command = { "refs", "migrate" }, option = "--contains" },
    { command = { "refs", "migrate" }, option = "--merged" },
    { command = { "refs", "migrate" }, option = "--no-contains" },
    { command = { "refs", "migrate" }, option = "--no-merged" },
    { command = { "refs", "migrate" }, option = "--points-at" },
    { command = { "refs", "optimize" }, option = "--contains" },
    { command = { "refs", "optimize" }, option = "--merged" },
    { command = { "refs", "optimize" }, option = "--no-contains" },
    { command = { "refs", "optimize" }, option = "--no-merged" },
    { command = { "refs", "optimize" }, option = "--points-at" },
    { command = { "refs", "rename" }, option = "--contains" },
    { command = { "refs", "rename" }, option = "--merged" },
    { command = { "refs", "rename" }, option = "--no-contains" },
    { command = { "refs", "rename" }, option = "--no-merged" },
    { command = { "refs", "rename" }, option = "--points-at" },
    { command = { "refs", "update" }, option = "--contains" },
    { command = { "refs", "update" }, option = "--merged" },
    { command = { "refs", "update" }, option = "--no-contains" },
    { command = { "refs", "update" }, option = "--no-merged" },
    { command = { "refs", "update" }, option = "--points-at" },
    { command = { "refs", "verify" }, option = "--contains" },
    { command = { "refs", "verify" }, option = "--merged" },
    { command = { "refs", "verify" }, option = "--no-contains" },
    { command = { "refs", "verify" }, option = "--no-merged" },
    { command = { "refs", "verify" }, option = "--points-at" },
    { command = "replace" },
    { command = "replace", option = "--edit" },
    { command = "replace", option = "--graft" },
    { command = "replay" },
    { command = "replay", option = "--ancestry-path" },
    { command = "replay", option = "--onto" },
    { command = "rev-list" },
    { command = "rev-list", option = "--ancestry-path" },
    { command = "shortlog", option = "--ancestry-path" },
    { command = { "stash", "import" } },
    { command = { "stash", "store" } },
    { command = "tag", option = "--no-contains" },
}, add_commit)

-- A tag is a ref, so every slot that already takes a branch takes a tag too;
-- describe in particular resolves a tag and nothing else by default.
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
    { command = "verify-tag" },
    { command = "tag" },
    { command = { "bisect", "start" }, multiple = true },
    { command = "branch",              option = "--set-upstream-to" },
    { command = "branch",              option = "--points-at" },
    { command = "tag",                 option = "--points-at" },
    { command = "rebase",              option = "--onto" },
    { command = "restore",             option = "--source" },
}, add_tag)

psc.on({
    { command = "checkout" },
    { command = "switch" }
}, add_remote_branch)

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
}, add_remote)

psc.on({
    { command = "stage",            multiple = true },
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
    { command = "annotate" }
}, add_tracked_files)

psc.on({ command = "mergetool" }, add_conflicts)

psc.on({
    { command = "config" },
    { command = { "config", "unset" } },
    { command = { "config", "get" } }
}, function()
    psc.add(psc.mount_items({ "next", "config", "next", "set", "next" }))
    add_alias_keys()
end)

psc.on({ command = { "config", "set" } }, add_alias_keys)

psc.on({}, add_aliases)
