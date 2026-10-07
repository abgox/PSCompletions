psc.on({ option = "--plugin" }, function()
    local pkg = psc.json("package.json")
    if pkg and pkg.devDependencies then
        for k, _ in pairs(pkg.devDependencies) do
            if k:find("prettier") then psc.add({ name = k }) end
        end
    end
end)
