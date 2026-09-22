local function add_scripts()
    local pkg = psc.json("package.json") or {}
    for name, cmd in pairs(pkg.scripts or {}) do
        psc.add({ name = name, tip = cmd })
    end
end

psc.on({}, add_scripts)
