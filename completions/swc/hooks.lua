psc.on({ option = "--config-file" }, function()
    for _, p in ipairs(psc.glob(".swcrc") or {}) do psc.add({ name = p }) end
    for _, p in ipairs(psc.glob("swc.config.{js,json}") or {}) do psc.add({ name = p }) end
end)
