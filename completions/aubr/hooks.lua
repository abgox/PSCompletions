local cs = {}

if psc.current.option_like then
    return completions
end

local pkg = psc.json("package.json")
if not pkg then
    return completions
end

if psc.has_unknown() then
    return completions
end

for k, v in pairs(pkg.scripts or {}) do
    psc.add(cs, { name = k, tip = v })
end

return psc.merge(cs)
