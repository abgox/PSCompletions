local function add_targets()
    local lines = psc.run({ "rustc", "--print", "target-list" })
    if not lines then return end
    for _, line in ipairs(lines) do
        local t = psc.trim(line)
        if t ~= "" then psc.add({ name = t, tip = "target" }) end
    end
end

local function add_lints()
    -- query rustc -W help to list lints (best effort)
    local lines = psc.run({ "rustc", "-W", "help" })
    if not lines then return end
    for _, line in ipairs(lines) do
        local lint = line:match("^%s+([%w%-_]+)%s")
        if lint and not lint:match("^rustc") then
            psc.add({ name = lint, tip = psc.trim(line) })
        end
    end
end

psc.on({ option = "--target" }, add_targets)

psc.on({
    { option = "--allow" },
    { option = "--warn" },
    { option = "--deny" },
    { option = "--forbid" }
}, add_lints)
