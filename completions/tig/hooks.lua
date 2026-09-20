local function add_refs()
    psc.add(psc.items(psc.run({ "git", "branch", "--format=%(refname:short)" }) or {}, function(b)
        -- Detached HEAD shows up as a "(HEAD detached ...)" pseudo-ref.
        if not b:match("^%(.+ detach") then
            return { name = b, tip = "branch --- " .. b }
        end
    end))
    psc.add(psc.items(psc.run({ "git", "tag", "-l" }) or {}, function(t)
        return { name = t, tip = "tag --- " .. t }
    end))
    psc.add({ name = "HEAD", tip = "HEAD --- the currently checked out commit" })
end

-- `tig blame path` takes a path, not a rev, as its first positional.
local function add_files()
    psc.add(psc.items(psc.ls(".") or {}, function(e)
        if not e.is_dir then
            return { name = e.name }
        end
    end))
end

psc.on({
    {},
    { command = "log" },
    { command = "show" },
    { command = "reflog" },
}, add_refs)

psc.on({ command = "blame" }, add_files)
