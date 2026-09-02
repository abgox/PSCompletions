local function add_paths()
    psc.add(psc.items(psc.run({ "zoxide", "query", "--list" }) or {}))
end

psc.on({
    { command = "query" },
    { command = "add",    multiple = true },
    { command = "remove", multiple = true }
}, add_paths)
