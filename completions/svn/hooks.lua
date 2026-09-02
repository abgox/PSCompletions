local function add_wc_files()
    for _, line in ipairs(psc.run({ "svn", "status" }) or {}) do
        local path = line:match("^%s*%S%s+%.?%s*(%S+)")
        if path then psc.add({ name = path, tip = line }) end
    end
end

local function add_svn_ls()
    for _, line in ipairs(psc.run({ "svn", "list" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" then psc.add({ name = name, tip = "repo" }) end
    end
end

local function add_changelists()
    for _, line in ipairs(psc.run({ "svn", "status" }) or {}) do
        local cl = line:match("--- Changelist '([^']+)'")
        if cl then psc.add({ name = cl, tip = "changelist" }) end
    end
end

psc.on({
    { command = "add" },
    { command = "delete" },
    { command = "commit" },
    { command = "revert" },
    { command = "status" },
    { command = "diff" },
    { command = "cat" },
    { command = "info" },
    { command = "propget" },
    { command = "propset" }
}, add_wc_files)

psc.on({ command = "list" }, add_svn_ls)

psc.on({
    { command = "changelist", multiple = true },
    { option = "--changelist" }
}, add_changelists)
