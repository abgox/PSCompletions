local function add_config()
    for _, p in ipairs(psc.glob("rslint.config.{js,mjs,ts,mts,cjs,cts}") or {}) do psc.add({ name = p }) end
end

psc.on({ option = "--config" }, add_config)
