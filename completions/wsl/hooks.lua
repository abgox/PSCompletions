local function add_dis()
    for _, line in ipairs(psc.run({ "wsl", "-l", "-q" }) or {}) do
        local d = psc.trim((line:gsub("%z", "")))
        if d ~= "" then
            psc.add({ name = d })
        end
    end
end

psc.on({
    { option = "--distribution" },
    { option = "--set-default" },
    { option = "--terminate" },
    { option = "--unregister" },
    { option = "--export" }
}, add_dis)
