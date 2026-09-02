psc.on({}, function()
    for _, p in ipairs(psc.glob("**/*.{js,ts,jsx,tsx,mjs,cjs}") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--tsconfig" }, function()
    for _, p in ipairs(psc.glob("tsconfig*.json") or {}) do psc.add({ name = p }) end
end)
