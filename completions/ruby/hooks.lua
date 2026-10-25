local function add_encodings()
    for _, name in ipairs(psc.run({ "ruby", "-e", "puts Encoding.name_list" }) or {}) do
        if name ~= "" then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = "Ruby encoding name",
                    ["zh-CN"] = "Ruby 编码名称",
                },
            })
        end
    end
end

psc.on({
    { option = "--encoding" },
    { option = "--external-encoding" },
    { option = "--internal-encoding" },
}, add_encodings)
