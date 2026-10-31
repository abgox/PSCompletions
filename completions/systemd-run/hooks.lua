local function add_slices()
    local argv = { "systemctl" }
    for _, token in ipairs(psc.tokens) do
        if token.name == "--user" then
            table.insert(argv, "--user")
            break
        end
    end
    table.insert(argv, "list-units")
    table.insert(argv, "--type=slice")
    table.insert(argv, "--all")
    table.insert(argv, "--no-legend")
    table.insert(argv, "--plain")
    for _, line in ipairs(psc.run(argv) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name })
        end
    end
end

psc.on({ option = "--slice" }, add_slices)
