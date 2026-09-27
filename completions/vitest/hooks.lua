local function add_config()
    for _, p in ipairs(psc.glob("vitest.config.{js,ts,mjs,cjs}") or {}) do psc.add({ name = p }) end
    for _, p in ipairs(psc.glob("vite.config.{js,ts,mjs,cjs}") or {}) do psc.add({ name = p }) end
end

psc.on({ option = "--config" }, add_config)
