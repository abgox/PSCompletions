local function add_targets()
    local lines = psc.run({ "rustc", "--print", "target-list" })
    if not lines then
        -- fallback via rustup
        lines = psc.run({ "rustup", "target", "list" })
        if lines then
            for _, line in ipairs(lines) do
                local t = line:match("^(%S+)")
                if t then psc.add({ name = t, tip = line }) end
            end
            return
        end
        return
    end
    for _, line in ipairs(lines) do
        local t = psc.trim(line)
        if t ~= "" then psc.add({ name = t, tip = "target" }) end
    end
end

local function add_crate_types()
    -- already static in manifest, but provide via hook as well for completeness
    local types = { "bin", "lib", "rlib", "dylib", "cdylib", "staticlib", "proc-macro" }
    for _, n in ipairs(types) do psc.add({ name = n }) end
end

local function add_editions()
    for _, e in ipairs({ "2015", "2018", "2021", "2024" }) do
        psc.add({ name = e, tip = "edition " .. e })
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

psc.on({ option = "--crate-type" }, add_crate_types)

psc.on({ option = "--edition" }, add_editions)

psc.on({
    { option = "--allow" },
    { option = "--warn" },
    { option = "--deny" },
    { option = "--forbid" }
}, add_lints)

psc.on({ option = "--cap-lints" }, function()
    for _, n in ipairs({ "allow", "warn", "deny", "forbid" }) do psc.add({ name = n }) end
end)
