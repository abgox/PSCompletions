psc.on({
    {},
    { command = "build" },
    { command = "preview" },
    { command = "optimize" },
    { option = "--config" },
}, function()
    for _, p in ipairs(psc.glob("vite.config.{js,ts,mjs,cjs,mts,cts}") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--mode" }, function()
    psc.add({ name = "development", tip = "development mode" })
    psc.add({ name = "production", tip = "production mode" })
end)
