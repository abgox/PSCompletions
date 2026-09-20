local function add_config()
    for _, p in ipairs(psc.glob("rspack.config.{js,ts,mjs,cjs,mts,cts}") or {}) do psc.add({ name = p }) end
end

psc.on({ option = "--config" }, add_config)
