local function add_users()
    if psc.platform == "macos" then
        psc.add(psc.items(psc.run({ "dscl", ".", "-list", "/Users" }) or {}))
        return
    end

    for _, line in ipairs(psc.split(psc.read("/etc/passwd") or "", "\n")) do
        local name = line:match("^([^:]+):")
        if name and name ~= "+" and name ~= "-" then
            psc.add({ name = name })
        end
    end
end

psc.on({}, add_users)
