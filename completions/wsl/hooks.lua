local cs = {}

local options = {
    "--distribution", "-d",
    "--set-default", "-s",
    "--terminate", "-t",
    "--unregister",
    "--export"
}
local dis = psc.run({ "wsl", "-l", "-q" }) or {}

if not psc.opts[1] then
    if #dis > 0 then
        for _, o in ipairs(options) do
            psc.set_symbol(o, "switch")
        end
    end
end

if not psc.contains(options, psc.opts[#psc.opts]) then
    return completions
end

for _, line in ipairs(psc.run({ "wsl", "-l", "-q" }) or {}) do
    local distro = psc.trim((line:gsub("%z", "")))
    psc.add(cs, {
        name = distro,
        tip = {
            ["en-US"] = "WSL distro",
            ["zh-CN"] = "WSL 发行版"
        }
    })
end

return psc.merge(cs)
