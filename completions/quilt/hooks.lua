local function add_series()
    psc.add(psc.items(psc.run({ "quilt", "series" }) or {}))
end

local function add_applied()
    psc.add(psc.items(psc.run({ "quilt", "applied" }) or {}))
end

local function add_unapplied()
    psc.add(psc.items(psc.run({ "quilt", "unapplied" }) or {}))
end

psc.on({
    { command = "delete" },
    { command = "files" },
    { command = "files", option = "--combine" },
    { command = "header" },
    { command = "mail" },
    { command = "previous" },
    { command = "rename", option = "-P" },
    { command = "unapplied" },
}, add_series)

psc.on({
    { command = "add", option = "-P" },
    { command = "annotate", option = "-P" },
    { command = "applied" },
    { command = "diff", option = "-P" },
    { command = "diff", option = "--combine" },
    { command = "graph" },
    { command = "pop" },
    { command = "refresh" },
    { command = "remove", option = "-P" },
    { command = "revert", option = "-P" },
}, add_applied)

psc.on({
    { command = "next" },
    { command = "push" },
}, add_unapplied)
