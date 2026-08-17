if psc.current.option_like then
    return completions
end

local cs = {}
local namespaces = {}
for _, line in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
    local n = line:match("^namespace/(.*)$")
    if n then
        namespaces[#namespaces + 1] = n
    end
end
for _, n in ipairs(namespaces) do
    psc.add(cs, { name = n })
end

return psc.merge(cs)
