local cs = {}

if psc.current.option_like then
    return completions
end

if psc.cmds[1] and not psc.has_unknown() then
    for _, line in ipairs(psc.run({ "sc", "query", "state=", "all" }) or {}) do
        local name = line:match("^SERVICE_NAME:%s+(%S+)")
        if name then
            psc.add(cs, {
                name = name,
                tip = {
                    ["en-US"] = "Windows service --- " .. name,
                    ["zh-CN"] = "Windows 服务 --- " .. name
                }
            })
        end
    end
end

return psc.merge(cs)
