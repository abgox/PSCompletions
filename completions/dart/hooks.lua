local function add_run_packages()
    local config = ".dart_tool/package_config.json"
    for i, token in ipairs(psc.tokens) do
        if token.type == "option"
            and (psc.eq(token.name, "--packages") or psc.eq(token.name, "--packages=")) then
            local value = psc.tokens[i + 1]
            if value and value.type == "value" then
                config = value.input
            end
            break
        end
    end
    local data = psc.json(config)
    local packages = data and data.packages or {}
    psc.add(psc.items(packages, function(entry)
        if entry and entry.name then
            return { name = entry.name }
        end
    end))
end

-- dependency names come from pubspec.yaml; sections may be absent or malformed
local function add_pubspec_deps()
    local pubspec = psc.yaml("pubspec.yaml")
    if type(pubspec) ~= "table" then
        return
    end
    for _, section in ipairs({ "dependencies", "dev_dependencies", "dependency_overrides" }) do
        local deps = pubspec[section]
        if type(deps) == "table" then
            for name, constraint in pairs(deps) do
                if type(constraint) == "string" then
                    psc.add({ name = name, tip = constraint })
                else
                    psc.add({ name = name })
                end
            end
        end
    end
end

-- `dart help` takes the tool's own subcommands: mount them, never copy them
psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)

psc.on({ command = "run" }, add_run_packages)

psc.on({
    { command = { "pub", "remove" }, multiple = true },
    { command = { "pub", "upgrade" }, multiple = true },
    { command = { "pub", "downgrade" }, multiple = true },
}, add_pubspec_deps)
