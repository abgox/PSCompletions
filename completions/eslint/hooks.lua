psc.on({}, function()
    for _, p in ipairs(psc.glob("**/*.{js,ts,jsx,tsx,cjs,mjs}") or {}) do
        psc.add({ name = p })
    end
end)

psc.on({ option = "--config" }, function()
    for _, p in ipairs(psc.glob("eslint.config.{js,mjs,cjs,ts,mts,cts}") or {}) do
        psc.add({ name = p })
    end
    for _, p in ipairs(psc.glob(".eslintrc.{js,json,cjs}") or {}) do
        psc.add({ name = p })
    end
end)
