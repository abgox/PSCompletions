local function add_targets()
    for _, line in ipairs(psc.run({ "xmake", "show", "-l", "targets" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" and not name:match("^Targets:") then
            psc.add({ name = name, tip = "target" })
        end
    end
end

psc.on({
    { command = "build" },
    { command = "clean" },
    { command = "run" },
    { command = "install" },
    { command = "package" },
    { command = "require" },
    { command = "test" },
    { command = "uninstall" }
}, add_targets)
