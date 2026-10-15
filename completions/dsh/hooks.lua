local function add_profiles()
    local home = psc.env("DSH_HOME") or ""
    if home == "" then
        local userhome = psc.env("HOME") or psc.env("USERPROFILE") or ""
        if userhome == "" then return end
        home = psc.path(userhome, ".dsh")
    end
    -- the CLI rejects this name in any letter case, so offering it completes a rejected invocation
    for _, e in ipairs(psc.ls(psc.path(home, "profiles")) or {}) do
        if e.is_dir and e.name:lower() ~= "desktop" then
            psc.add({
                name = e.name,
                tip = {
                    ["en-US"] = "Custom profile under $DSH_HOME/profiles.",
                    ["zh-CN"] = "$DSH_HOME/profiles 下的自定义 profile。",
                },
            })
        end
    end
end

psc.on({
    {},
    { option = "--profile" },
}, add_profiles)
