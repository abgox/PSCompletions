psc.on({}, function()
    for _, p in ipairs(psc.glob("**/*.{js,ts,jsx,tsx}") or {}) do psc.add({ name = p, tip = p }) end
end)

psc.on({ option = "--config" }, function()
    for _, p in ipairs(psc.glob("{.oxlintrc,oxlint}.json") or {}) do psc.add({ name = p, tip = p }) end
end)

psc.on({ option = "--tsconfig" }, function()
    for _, p in ipairs(psc.glob("tsconfig*.json") or {}) do psc.add({ name = p, tip = p }) end
end)
