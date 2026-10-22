local function add_types()
    for _, line in ipairs(psc.run({ "tgrep", "--type-list" }) or {}) do
        local name, globs = line:match("^([^:]+):%s*(.*)$")
        if name and name ~= "" then
            psc.add({ name = name, tip = globs ~= "" and globs or nil })
        end
    end
end

psc.on({
    { option = "--type" },
    { option = "--type-not" },
    { option = "--type-clear" }
}, add_types)

psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
