local function add_tests()
    for _, p in ipairs(psc.glob("**/*.{test,spec}.{ts,js,tsx,jsx,mts,cts}") or {}) do psc.add({ name = p }) end
end

local function add_config()
    for _, p in ipairs(psc.glob("vitest.config.{js,ts,mjs,cjs}") or {}) do psc.add({ name = p }) end
    for _, p in ipairs(psc.glob("vite.config.{js,ts,mjs,cjs}") or {}) do psc.add({ name = p }) end
end

psc.on({}, function()
    add_config()
    add_tests()
end)

psc.on({
    { command = "run" },
    { command = "watch" },
    { command = "dev" },
    { command = "bench" },
    { command = "related" },
    { command = "list" }
}, add_tests)

psc.on({ option = "--config" }, add_config)

psc.on({ option = "--root" }, function()
    for _, e in ipairs(psc.ls(".") or {}) do
        if e.is_dir then psc.add({ name = e.name }) end
    end
end)
