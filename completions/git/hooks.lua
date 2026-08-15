local function add_branch(cs)
    for _, b in ipairs(psc.run({ "git", "branch", "--format=%(refname:lstrip=2)" }) or {}) do
        if not b:match("^%(%w+ detach") then
            psc.add(cs, { name = b, tip = "branch --- " .. b })
        end
    end
end

local function add_head(cs)
    for _, h in ipairs({ "HEAD", "FETCH_HEAD", "ORIG_HEAD", "MERGE_HEAD" }) do
        local tip = psc.join(psc.run({ "git", "show", h, "--relative-date", "-q" }) or {}, "\n")
        psc.add(cs, { name = h, tip = tip })
    end
end

local function add_commit(cs)
    local max = tonumber(psc.config.max_commit) or 30
    local sep = "PSCOMPLETIONS_COMMIT_SEP"
    local args = { "git", "log", "--pretty=format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n" .. sep }
    -- `max_commit` = -1 means "all commits"; git log -n only accepts a positive count
    if max ~= -1 then
        table.insert(args, "-n")
        table.insert(args, tostring(max))
    end
    local lines = psc.run(args) or {}
    local buf = {}
    for _, l in ipairs(lines) do
        if l == sep then
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
                psc.add(cs, { name = buf[1], tip = psc.join(tip_parts, "\n") })
            end
            buf = {}
        else
            table.insert(buf, l)
        end
    end
end

local function add_stash(cs)
    for _, line in ipairs(psc.run({ "git", "stash", "list" }) or {}) do
        local id = line:match("stash@{(%d+)}")
        if id then
            psc.add(cs, { name = id, tip = line })
        end
    end
end

local function add_remote(cs)
    psc.add(cs, psc.items(psc.run({ "git", "remote" }) or {}, function(name)
        return { name = name, tip = "remote --- " .. name }
    end))
end

local function add_tag(cs)
    psc.add(cs, psc.items(psc.run({ "git", "tag", "-l" }) or {}, function(name)
        return { name = name, tip = "tag --- " .. name }
    end))
end

local cs = {}

if psc.current.option_like then
    return completions
end

local cmd1, cmd2 = psc.cmds[1], psc.cmds[2]
local last_path = psc.cmds[#psc.cmds]
local lo = psc.opts[#psc.opts]
local clean = not psc.has_unknown()

if not cmd1 then
    local commits = {}
    add_commit(commits)
    if #commits > 0 then
        psc.set_symbol("revert", "switch")
        psc.set_symbol("show", "switch")
    end
elseif psc.eq(cmd1, "config") then
    local keys = psc.mount_items({ "next", "config", "set", "next" })
    if #keys > 0 then
        psc.set_symbol("get", "switch")
        psc.set_symbol("unset", "switch")
    end
elseif psc.eq(cmd1, "branch") then
    local commits = {}
    add_commit(commits)
    if #commits > 0 then
        psc.set_symbol("--contains", "switch")
        psc.set_symbol("--merged", "switch")
        psc.set_symbol("--no-merged", "switch")
    end
    local branches = {}
    add_branch(branches)
    if #branches > 0 then
        psc.set_symbol("--copy", "switch")
        psc.set_symbol("--move", "switch")
        psc.set_symbol("-d", "switch")
    end
elseif psc.eq(cmd1, "commit") then
    local commits = {}
    add_commit(commits)
    if #commits > 0 then
        psc.set_symbol("--fixup", "switch")
        psc.set_symbol("--squash", "switch")
    end
elseif psc.eq(cmd1, "stash") then
    local stashes = {}
    add_stash(stashes)
    if #stashes > 0 then
        psc.set_symbol("apply", "switch")
        psc.set_symbol("drop", "switch")
        psc.set_symbol("pop", "switch")
    end
elseif psc.eq(cmd1, "remote") then
    local remotes = psc.items(psc.run({ "git", "remote" }) or {}, function(name)
        return { name = name, tip = "remote --- " .. name }
    end)
    if #remotes > 0 then
        psc.set_symbol("remove", "switch")
    end
elseif psc.eq(cmd1, "tag") then
    local tags = {}
    add_tag(tags)
    if #tags > 0 then
        psc.set_symbol("--delete", "switch")
        psc.set_symbol("--verify", "switch")
    end
    local commits = {}
    add_commit(commits)
    if #commits > 0 then
        psc.set_symbol("--contains", "switch")
        psc.set_symbol("--merged", "switch")
        psc.set_symbol("--no-contains", "switch")
        psc.set_symbol("--no-merged", "switch")
    end
end

if psc.eq(cmd1, "add") then
    for _, line in ipairs(psc.run({ "git", "status", "--porcelain" }) or {}) do
        local f = line:match("^.[MD] (.+)$") or line:match("^%?%? (.+)$")
        if f then
            psc.add(cs, { name = f, tip = line })
        end
    end
elseif psc.contains({ "bisect", "checkout", "cherry", "cherry-pick", "describe", "format-patch", "log", "merge-base", "notes", "shortlog" }, cmd1) then
    if clean then
        add_branch(cs)
        add_head(cs)
        add_commit(cs)
    end
elseif psc.eq(cmd1, "config") then
    if psc.contains({ "unset", "get" }, last_path) then
        -- Reuse config.set's keys: get/unset need the key names (their own level)
        psc.add(cs, psc.mount_items({ "next", "config", "set", "next" }))
    end
elseif psc.eq(cmd1, "diff") then
    add_commit(cs)
elseif psc.eq(cmd1, "grep") then
    if clean then
        add_commit(cs)
    end
elseif psc.eq(cmd1, "rebase") then
    add_branch(cs)
    add_head(cs)
    add_commit(cs)
    if psc.eq(lo, "--strategy") then
        for _, s in ipairs({ "resolve", "recursive", "ours", "subtree", "octopus" }) do
            psc.add(cs, { name = s, tip = "strategy --- " .. s })
        end
    end
elseif psc.eq(cmd1, "reset") then
    if clean then
        add_head(cs)
        add_commit(cs)
    end
elseif psc.eq(cmd1, "revert") then
    if clean then
        add_commit(cs)
    end
elseif psc.eq(cmd1, "show") then
    if clean then
        add_head(cs)
        add_commit(cs)
    end
elseif psc.eq(cmd1, "switch") then
    if clean then
        add_branch(cs)
    end
elseif psc.eq(cmd1, "branch") then
    if psc.contains({ "--move", "--copy", "-d" }, lo) then
        add_branch(cs)
    elseif psc.contains({ "--contains", "--merged", "--no-merged" }, lo) then
        add_commit(cs)
    elseif psc.eq(lo, "--points-at") then
        add_branch(cs)
        add_head(cs)
        add_commit(cs)
        add_tag(cs)
    elseif psc.eq(lo, "--set-upstream-to") then
        add_branch(cs)
    end
elseif psc.eq(cmd1, "commit") then
    if clean and psc.contains({ "--reedit-message", "--fixup", "--squash" }, lo) then
        add_commit(cs)
    end
elseif psc.eq(cmd1, "merge") then
    if clean then
        add_branch(cs)
    end
elseif psc.eq(cmd1, "stash") then
    if clean and psc.contains({ "show", "pop", "apply", "drop" }, cmd2) then
        add_stash(cs)
    end
elseif psc.contains({ "push", "pull", "fetch" }, cmd1) then
    if clean then
        add_remote(cs)
    end
    if psc.eq(cmd1, "fetch") and psc.eq(lo, "--shallow-exclude") then
        add_branch(cs)
        add_tag(cs)
    end
elseif psc.eq(cmd1, "remote") then
    if psc.contains({ "rename", "remove" }, cmd2) then
        add_remote(cs)
    end
elseif psc.eq(cmd1, "tag") then
    if psc.contains({ "--delete", "--verify" }, lo) then
        add_tag(cs)
    elseif psc.contains({ "--contains", "--merged", "--no-contains", "--no-merged" }, lo) then
        add_commit(cs)
    elseif psc.eq(lo, "--points-at") then
        add_branch(cs)
        add_head(cs)
        add_commit(cs)
        add_tag(cs)
    end
end

return psc.merge(cs)
