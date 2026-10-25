local function add_tasks()
    for _, line in ipairs(psc.run({ "rake", "-AT" }) or {}) do
        local name, tip = line:match("^rake%s+(%S+)%s+#%s*(.*)$")
        if name then
            psc.add({
                name = name,
                tip = tip ~= "" and tip or nil,
            })
        end
    end
end

psc.on({ multiple = true }, add_tasks)
