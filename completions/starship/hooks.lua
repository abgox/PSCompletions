local function add_presets()
    for _, line in ipairs(psc.run({ "starship", "preset", "list" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" then psc.add({ name = name, tip = "preset" }) end
    end
end

local function add_modules()
    for _, line in ipairs(psc.run({ "starship", "module", "--list" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" then psc.add({ name = name, tip = "module" }) end
    end
    -- fallback via starship explain
    for _, line in ipairs(psc.run({ "starship", "explain" }) or {}) do
        local mod = line:match("(%S+)%s+%-")
        if mod then psc.add({ name = mod, tip = line }) end
    end
end

local function add_configs()
    -- starship config file paths
    for _, p in ipairs(psc.glob("starship.toml") or {}) do
        psc.add({ name = p, tip = "config" })
    end
    local cfg = psc.env("STARSHIP_CONFIG")
    if cfg then psc.add({ name = cfg, tip = "STARSHIP_CONFIG" }) end
end

psc.on({ command = "preset" }, add_presets)

psc.on({
    { command = "module" },
    { command = "toggle" }
}, add_modules)

psc.on({ command = "config" }, add_configs)
