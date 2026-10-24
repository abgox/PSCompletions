local function add_profiles()
    local dir = psc.env("UNISON")
    if not dir or dir == "" then
        local home = psc.env("HOME") or psc.env("USERPROFILE")
        if not home or home == "" then
            return
        end
        dir = psc.path(home, ".unison")
    end

    local tip = { ["en-US"] = "Unison profile", ["zh-CN"] = "Unison 配置文件" }
    for _, entry in ipairs(psc.ls(dir) or {}) do
        local name = entry.name:match("^(.*)%.prf$")
        if name and name ~= "" and not entry.is_dir then
            psc.add({ name = name, tip = tip })
        end
    end
end

psc.on({
    {},
    { option = "-include" }
}, add_profiles)
