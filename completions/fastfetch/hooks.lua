local function add_logos()
    for _, line in ipairs(psc.run({ "fastfetch", "--list-logos" }) or {}) do
        for name in line:gmatch('"([^"]+)"') do
            psc.add({ name = name })
        end
    end
end

psc.on({ option = "--logo" }, add_logos)
