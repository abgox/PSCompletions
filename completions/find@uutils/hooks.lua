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

local function add_groups()
    if psc.platform == "macos" then
        psc.add(psc.items(psc.run({ "dscl", ".", "-list", "/Groups" }) or {}))
        return
    end

    for _, line in ipairs(psc.split(psc.read("/etc/group") or "", "\n")) do
        local name = line:match("^([^:]+):")
        if name and name ~= "+" and name ~= "-" then
            psc.add({ name = name })
        end
    end
end

local function add_fstypes()
    local seen = {}
    local function add(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            psc.add({ name = name })
        end
    end

    if psc.platform == "linux" then
        for _, line in ipairs(psc.split(psc.read("/proc/mounts") or "", "\n")) do
            add(line:match("^%S+%s+%S+%s+(%S+)"))
        end
    elseif psc.platform == "macos" then
        for _, line in ipairs(psc.run({ "mount" }) or {}) do
            add(line:match("%(([%w%._%-]+)[,%)]"))
        end
    end
end

psc.on({ option = "-user" }, add_users)

psc.on({ option = "-group" }, add_groups)

psc.on({ option = "-fstype" }, add_fstypes)
