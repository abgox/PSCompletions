local function add_users()
    if psc.platform == "macos" then
        for _, line in ipairs(psc.run({ "dscl", ".", "-list", "/Users", "UniqueID" }) or {}) do
            local name, uid = line:match("^(%S+)%s+(%-?%d+)")
            uid = tonumber(uid)
            if name and uid and uid >= 501 then
                psc.add({ name = name })
            end
        end
        return
    end

    -- chsh edits the local password file; keep regular accounts only, since system accounts are not targets.
    for _, line in ipairs(psc.split(psc.read("/etc/passwd") or "", "\n")) do
        local name, uid = line:match("^([^:]+):[^:]*:(%d+):")
        uid = tonumber(uid)
        if name and uid and uid >= 1000 and uid < 65534 then
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

psc.on({ option = "--shell" }, add_shells)
