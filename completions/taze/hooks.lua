local function add_deps()
    local pkg = psc.json("package.json")
    if not pkg then return end
    for k, v in pairs(pkg.dependencies or {}) do
        psc.add({ name = k, tip = "dependency: " .. k .. " (" .. v .. ")" })
    end
    for k, v in pairs(pkg.devDependencies or {}) do
        psc.add({ name = k, tip = "devDependency: " .. k .. " (" .. v .. ")" })
    end
    for k, v in pairs(pkg.peerDependencies or {}) do
        psc.add({ name = k, tip = "peerDependency: " .. k .. " (" .. v .. ")" })
    end
    for k, v in pairs(pkg.optionalDependencies or {}) do
        psc.add({ name = k, tip = "optionalDependency: " .. k .. " (" .. v .. ")" })
    end
end

psc.on({
    { option = "--include" },
    { option = "--exclude" },
    { option = "--maturity-period-exclude" }
}, add_deps)
