psc.on({ option = "--config-path" }, function()
    for _, p in ipairs(psc.glob("biome.{json,jsonc}") or {}) do psc.add({ name = p }) end
end)
