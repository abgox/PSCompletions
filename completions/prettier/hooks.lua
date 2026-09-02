psc.on({}, function()
    for _, p in ipairs(psc.glob("**/*.{js,ts,jsx,tsx,json,css,scss,md,html,yml,yaml}") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--config" }, function()
    for _, p in ipairs(psc.glob(".prettierrc*") or {}) do psc.add({ name = p }) end
    for _, p in ipairs(psc.glob("prettier.config.{js,cjs,mjs}") or {}) do psc.add({ name = p }) end
end)

psc.on({ option = "--plugin" }, function()
    local pkg = psc.json("package.json")
    if pkg and pkg.devDependencies then
        for k, _ in pairs(pkg.devDependencies) do
            if k:find("prettier") then psc.add({ name = k }) end
        end
    end
end)
