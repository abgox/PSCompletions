if psc.platform ~= "windows" then
    return
end

local function add_services()
    for _, line in ipairs(psc.run({ "sc", "query", "state=", "all" }) or {}) do
        local name = line:match("^SERVICE_NAME:%s+(%S+)")
        if name then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = "Windows service --- " .. name,
                    ["zh-CN"] = "Windows 服务 --- " .. name
                }
            })
        end
    end
end

psc.on({ command = { "" } }, add_services)
