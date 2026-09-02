local function add_scripts()
    local pkg = psc.json("package.json")
    if not pkg then return end
    for k, v in pairs(pkg.scripts or {}) do
        psc.add({ name = k, tip = v })
    end
end

psc.on({}, add_scripts)
