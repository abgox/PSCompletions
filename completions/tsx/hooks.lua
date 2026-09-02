psc.on({
    {},
    { command = "watch" }
}, function()
    for _, p in ipairs(psc.glob("**/*.{ts,tsx,js,jsx,mts,cts}") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--tsconfig" }, function()
    for _, p in ipairs(psc.glob("tsconfig*.json") or {}) do psc.add({ name = p }) end
end)
