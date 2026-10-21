local function add_profiles(skip_static)
    local home = psc.env("DSH_HOME") or ""
    if home == "" then
        local userhome = psc.env("HOME") or psc.env("USERPROFILE") or ""
        if userhome == "" then return end
        home = psc.path(userhome, ".dsh")
    end
    -- the CLI rejects this name in any letter case, so offering it completes a rejected invocation
    -- default profiles are static command nodes (they carry per-profile options); only custom ones are injected
    local static = { acp = true, headless = true, sdk = true, ["sdk-minimal"] = true, web = true }
    for _, e in ipairs(psc.ls(psc.path(home, "profiles")) or {}) do
        if e.is_dir and e.name:lower() ~= "desktop" and not (skip_static and static[e.name]) then
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

local function add_custom_profiles()
    add_profiles(true)
end

psc.on({}, add_custom_profiles)

psc.on({ option = "--profile" }, add_custom_profiles)
