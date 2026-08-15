local cs = {}

if psc.current.option_like then
    return completions
end

local pkg = psc.json("package.json")
if not pkg then
    return completions
end

local cmd1 = psc.cmds[1]
if not cmd1 then
    for k, v in pairs(pkg.scripts or {}) do
        psc.add(cs, { name = k, tip = v })
    end
    if next(pkg.scripts or {}) ~= nil then
        psc.set_symbol("run", "switch")
    end
    if next(pkg.dependencies or {}) ~= nil or next(pkg.devDependencies or {}) ~= nil then
        psc.set_symbol("remove", "switch")
        psc.set_symbol("upgrade", "switch")
    end
elseif psc.eq(cmd1, "run") and not psc.has_unknown() then
    for k, v in pairs(pkg.scripts or {}) do
        psc.add(cs, { name = k, tip = v })
    end
elseif psc.contains({ "remove", "upgrade" }, cmd1) then
    for k, v in pairs(pkg.dependencies or {}) do
        psc.add(cs, { name = k, tip = "dependency: " .. k .. " (" .. v .. ")" })
    end
    for k, v in pairs(pkg.devDependencies or {}) do
        psc.add(cs, { name = k, tip = "devDependency: " .. k .. " (" .. v .. ")" })
    end
end

return psc.merge(cs)
