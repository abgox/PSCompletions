local function add_users()
    if psc.platform == "macos" then
        psc.add(psc.items(psc.run({ "dscl", ".", "-list", "/Users", "UniqueID" }) or {}))
        return
    end

    -- LOGIN is optional: without it the command changes the caller's own password, so keep regular accounts.
    for _, line in ipairs(psc.split(psc.read("/etc/passwd") or "", "\n")) do
        local name, uid = line:match("^([^:]+):[^:]*:(%d+):")
        uid = tonumber(uid)
        if name and uid and uid >= 1000 and uid < 65534 then
            psc.add({ name = name })
        end
    end
end

psc.on({}, add_users)
