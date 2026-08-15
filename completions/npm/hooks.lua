local cs = {}

if psc.current.option_like then
    return completions
end

local pkg = psc.json("package.json")
if not pkg then
    return completions
end

local cmd1 = psc.cmds[1]
if psc.eq(cmd1, "run-script") and not psc.has_unknown() then
    for k, v in pairs(pkg.scripts or {}) do
        psc.add(cs, { name = k, tip = v })
    end
elseif psc.contains({ "uninstall", "upgrade" }, cmd1) then
    for k, v in pairs(pkg.dependencies or {}) do
        psc.add(cs, { name = k, tip = "dependency: " .. k .. " (" .. v .. ")" })
    end
    for k, v in pairs(pkg.devDependencies or {}) do
        psc.add(cs, { name = k, tip = "devDependency: " .. k .. " (" .. v .. ")" })
    end
end

return psc.merge(cs)
