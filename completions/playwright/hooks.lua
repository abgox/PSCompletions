local function add_tests()
    for _, p in ipairs(psc.glob("**/*.{spec,test}.{ts,js,mjs,cjs,tsx,jsx}") or {}) do psc.add({ name = p }) end
    -- e2e folder fallback
    for _, p in ipairs(psc.glob("e2e/**/*.{ts,js}") or {}) do psc.add({ name = p }) end
end

local function add_config()
    for _, p in ipairs(psc.glob("playwright.config.{js,ts,mjs,cjs,mts,cts}") or {}) do psc.add({ name = p }) end
end

psc.on({}, function()
    add_config()
    add_tests()
end)

psc.on({ command = "test" }, add_tests)

psc.on({ command = "show-report" }, function()
    for _, p in ipairs(psc.glob("playwright-report/**/*") or {}) do psc.add({ name = p }) end
end)

psc.on({ command = "show-trace" }, function()
    for _, p in ipairs(psc.glob("**/*.zip") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--config" }, add_config)
