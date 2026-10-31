local function add_users()
    for _, line in ipairs(psc.split(psc.read("/etc/passwd") or "", "\n")) do
        local name = line:match("^([^:]+):")
        if name and name ~= "+" and name ~= "-" then
            psc.add({ name = name })
        end
    end
end

local function add_groups()
    for _, line in ipairs(psc.split(psc.read("/etc/group") or "", "\n")) do
        local name = line:match("^([^:]+):")
        if name and name ~= "+" and name ~= "-" then
            psc.add({ name = name })
        end
    end
end

psc.on({
    { option = "--add" },
    { option = "--administrators" },
    { option = "--delete" },
    { option = "--members" },
}, add_users)

psc.on({}, add_groups)
