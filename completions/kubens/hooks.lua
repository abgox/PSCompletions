local function add_namespaces()
    for _, line in ipairs(psc.run({ "kubectl", "get", "namespaces", "-o", "name" }) or {}) do
        local n = line:match("^namespace/(.*)$")
        if n then
            psc.add({ name = n })
        end
    end
end

psc.on({}, add_namespaces)
