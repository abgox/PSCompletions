psc.on({
    { command = "check" },
    { command = "ci" },
    { command = "format" },
    { command = "lint" },
    { command = "explain" },
    { command = "search" }
}, function()
    for _, p in ipairs(psc.glob("**/*.{js,ts,jsx,tsx,json,jsonc}") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--config-path" }, function()
    for _, p in ipairs(psc.glob("biome.{json,jsonc}") or {}) do psc.add({ name = p }) end
end)
