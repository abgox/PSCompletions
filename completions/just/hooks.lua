local cs = {}

if psc.current.option_like then
    return completions
end

if not psc.cmds[1] then
    for _, line in ipairs(psc.run({ "just", "--summary" }) or {}) do
        for word in line:gmatch("%S+") do
            psc.add(cs, { name = word })
        end
    end
end

return psc.merge(cs)
