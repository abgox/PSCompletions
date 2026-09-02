local function add_targets()
    for _, line in ipairs(psc.run({ "xmake", "show", "-l", "targets" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" and not name:match("^Targets:") then
            psc.add({ name = name, tip = "target" })
        end
    end
end

local function add_files()
    for _, p in ipairs(psc.glob("xmake.lua") or {}) do
        psc.add({ name = p, tip = "xmake" })
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

psc.on({
    { option = "--file" },
    { option = "--project" }
}, add_files)
