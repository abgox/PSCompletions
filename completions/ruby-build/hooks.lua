local function add_definitions()
    for _, name in ipairs(psc.run({ "ruby-build", "--definitions" }) or {}) do
        if name ~= "" then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = "Installable Ruby definition",
                    ["zh-CN"] = "可安装的 Ruby 定义",
                },
            })
        end
    end
end

psc.on({}, add_definitions)
