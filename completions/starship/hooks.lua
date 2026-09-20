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

psc.on({ command = "preset" }, add_presets)

psc.on({
    { command = "module" },
    { command = "toggle" }
}, add_modules)
