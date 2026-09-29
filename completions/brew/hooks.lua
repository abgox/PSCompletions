local function add_all()
    local results = psc.run_batch({ { "brew", "formulae" }, { "brew", "casks" } }) or {}
    psc.add(psc.items(psc.concat(results[1] or {}, results[2] or {})))
end

local function add_installed()
    for _, line in ipairs(psc.run({ "brew", "list", "--versions" }) or {}) do
        local name, ver = line:match("^(%S+)%s*(.-)%s*$")
        if name then
            if ver == "" then ver = nil end
            psc.add({ name = name, tip = ver })
        end
    end
end

local function add_taps()
    psc.add(psc.items(psc.run({ "brew", "tap" }) or {}))
end

psc.on({
    { command = "audit",            multiple = true },
    { command = "bottle",           multiple = true },
    { command = "bump",             multiple = true },
    { command = "bump-formula-pr" },
    { command = "cat",              multiple = true },
    { command = "deps",             multiple = true },
    { command = "desc",             multiple = true },
    { command = "edit",             multiple = true },
    { command = "fetch",            multiple = true },
    { command = "formula",          multiple = true },
    { command = "home",             multiple = true },
    { command = "info",             multiple = true },
    { command = "install",          multiple = true },
    { command = "log" },
    { command = "options",          multiple = true },
    { command = "source",           multiple = true },
    { command = "uses",             multiple = true },
    { command = "version-install" },
    { command = "vulns",            multiple = true },
}, add_all)

psc.on({
    { command = "gist-logs" },
    { command = "link",      multiple = true },
    { command = "linkage",   multiple = true },
    { command = "list",      multiple = true },
    { command = "migrate",   multiple = true },
    { command = "missing",   multiple = true },
    { command = "outdated",  multiple = true },
    { command = "pin",       multiple = true },
    { command = "postinstall",  multiple = true },
    { command = "reinstall", multiple = true },
    { command = "tab",       multiple = true },
    { command = "uninstall", multiple = true },
    { command = "unlink",    multiple = true },
    { command = "unpin",     multiple = true },
    { command = "upgrade",   multiple = true },
}, add_installed)

psc.on({
    { command = "readall",     multiple = true },
    { command = "tap" },
    { command = "tap-info",    multiple = true },
    { command = "untap",       multiple = true },
    { command = "update-reset",  multiple = true },
}, add_taps)
