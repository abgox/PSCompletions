local function add_services()
    local argv = { "busctl" }
    for _, token in ipairs(psc.tokens) do
        if token.name == "--user" then
            table.insert(argv, "--user")
            break
        end
    end
    table.insert(argv, "list")
    table.insert(argv, "--no-legend")
    table.insert(argv, "--no-pager")
    for _, line in ipairs(psc.run(argv) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

-- Every target takes one service as its first positional; only monitor,
-- capture and tree accept several.
psc.on({
    { command = "status" },
    { command = "monitor", multiple = true },
    { command = "capture", multiple = true },
    { command = "tree", multiple = true },
    { command = "introspect" },
    { command = "call" },
    { command = "get-property" },
    { command = "set-property" },
}, add_services)
