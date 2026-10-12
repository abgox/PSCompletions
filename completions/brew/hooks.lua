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

local function add_doctor_checks()
    psc.add(psc.items(psc.run({ "brew", "doctor", "--list-checks" }) or {}))
end

local function add_aliases()
    for _, line in ipairs(psc.run({ "brew", "alias" }) or {}) do
        local name = line:match("^brew alias (%S+)='(.-)'%s*$")
        if name then
            psc.add({ name = name })
        end
    end
end

local function add_commands()
    psc.add(psc.mount_items({ "next" }))
end

psc.on({
    { command = "audit",                      multiple = true },
    { command = "benchmark",                  multiple = true },
    { command = "bottle",                     multiple = true },
    { command = "bump",                       multiple = true },
    { command = "bump-cask-pr" },
    { command = "bump-compatibility-version", multiple = true },
    { command = "bump-formula-pr" },
    { command = "bump-revision",              multiple = true },
    { command = "bump-unversioned-casks",     multiple = true },
    { command = "cat",                        multiple = true },
    { command = "deps",                       multiple = true },
    { command = "desc",                       multiple = true },
    { command = "edit",                       multiple = true },
    { command = "extract" },
    { command = "fetch",                      multiple = true },
    { command = "formula",                    multiple = true },
    { command = "generate-zap" },
    { command = "homepage",                   multiple = true },
    { command = "info",                       multiple = true },
    { command = "install",                    multiple = true },
    { command = "livecheck",                  multiple = true },
    { command = "log" },
    { command = "options",                    multiple = true },
    { command = "source",                     multiple = true },
    { command = "test-bot" },
    { command = "unbottled",                  multiple = true },
    { command = "unpack",                     multiple = true },
    { command = "update-perl-resources",      multiple = true },
    { command = "update-python-resources",    multiple = true },
    { command = "uses",                       multiple = true },
    { command = "verify",                     multiple = true },
    { command = "version-install" },
    { command = "vulns",                      multiple = true },
}, add_all)

psc.on({
    { command = "cleanup",      multiple = true },
    { command = "gist-logs" },
    { command = "link",         multiple = true },
    { command = "linkage",      multiple = true },
    { command = "list",         multiple = true },
    { command = "migrate",      multiple = true },
    { command = "missing",      multiple = true },
    { command = "outdated",     multiple = true },
    { command = "pin",          multiple = true },
    { command = "post_install", multiple = true },
    { command = "reinstall",    multiple = true },
    { command = "tab",          multiple = true },
    { command = "test",         multiple = true },
    { command = "uninstall",    multiple = true },
    { command = "unlink",       multiple = true },
    { command = "unpin",        multiple = true },
    { command = "upgrade",      multiple = true },
}, add_installed)

psc.on({
    { command = "readall",      multiple = true },
    { command = "tap" },
    { command = "tap-info",     multiple = true },
    { command = "trust",        multiple = true },
    { command = "typecheck",    multiple = true },
    { command = "untap",        multiple = true },
    { command = "untrust",      multiple = true },
    { command = "update-reset", multiple = true },
}, add_taps)

psc.on({ command = "doctor", multiple = true }, add_doctor_checks)

psc.on({ command = "unalias", multiple = true }, add_aliases)

psc.on({
    { command = "as-console-user" },
    { command = "command" },
    { command = "debugger" },
    { command = "help" },
    { command = "prof" },
    { command = "setup-ruby" },
}, add_commands)
