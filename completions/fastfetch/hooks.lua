local function add_logos()
    for _, line in ipairs(psc.run({ "fastfetch", "--list-logos" }) or {}) do
        for name in line:gmatch('"([^"]+)"') do
            psc.add({ name = name })
        end
    end
end

local function add_configs()
    psc.add(psc.items(psc.glob("fastfetch.{json,toml}") or {}))
end

psc.on({ option = "--logo" }, add_logos)

psc.on({ option = "--config" }, add_configs)
