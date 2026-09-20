local function add_profiles()
    local patterns = { ".rsdoctor/manifest.json", "dist/stats.json", "stats.json" }
    for _, pat in ipairs(patterns) do
        for _, p in ipairs(psc.glob(pat) or {}) do psc.add({ name = p }) end
    end
end

psc.on({
    { option = "--profile" },
    { option = "--current" },
    { option = "--baseline" },
}, add_profiles)
