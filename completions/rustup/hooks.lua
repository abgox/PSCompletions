local function add_toolchains()
    psc.add(psc.items(psc.run({ "rustup", "toolchain", "list", "-q" }) or {}))
end

local function add_targets()
    psc.add(psc.items(psc.run({ "rustup", "target", "list", "-q" }) or {}))
end

local function add_installed_targets()
    psc.add(psc.items(psc.run({ "rustup", "target", "list", "--installed", "-q" }) or {}))
end

local function add_components()
    psc.add(psc.items(psc.run({ "rustup", "component", "list", "-q" }) or {}))
end

local function add_installed_components()
    psc.add(psc.items(psc.run({ "rustup", "component", "list", "--installed", "-q" }) or {}))
end

psc.on({
    { command = "default" },
    { command = "uninstall" },
    { command = "run" },
    { command = { "override", "set" } },
    { command = { "toolchain", "install" } },
    { command = { "toolchain", "uninstall" } }
}, add_toolchains)

psc.on({ command = { "target", "add" } }, add_targets)

psc.on({ command = { "target", "remove" } }, add_installed_targets)

psc.on({ command = { "component", "add" } }, add_components)

psc.on({ command = { "component", "remove" } }, add_installed_components)
