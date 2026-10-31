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

local function add_shells()
    for _, line in ipairs(psc.split(psc.read("/etc/shells") or "", "\n")) do
        local shell = line:match("^%s*([^#%s]%S*)")
        if shell then
            psc.add({ name = shell })
        end
    end
end

psc.on({}, add_users)

psc.on({
    { option = "--group" },
    { option = "--supp-group" },
}, add_groups)

psc.on({ option = "--shell" }, add_shells)
