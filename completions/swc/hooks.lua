psc.on({}, function()
    for _, p in ipairs(psc.glob("**/*.{js,ts,jsx,tsx,mjs,cjs}") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--config-file" }, function()
    for _, p in ipairs(psc.glob(".swcrc") or {}) do psc.add({ name = p }) end
    for _, p in ipairs(psc.glob("swc.config.{js,json}") or {}) do psc.add({ name = p }) end
end)
