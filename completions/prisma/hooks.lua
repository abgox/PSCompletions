local function add_config()
    for _, p in ipairs(psc.glob("prisma.config.{ts,js,mjs,cjs,mts,cts}") or {}) do psc.add({ name = p }) end
end

psc.on({ option = "--config" }, add_config)
