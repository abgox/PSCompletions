local function add_recipes()
    for _, line in ipairs(psc.run({ "just", "--summary" }) or {}) do
        for word in line:gmatch("%S+") do
            psc.add({ name = word })
        end
    end
end

psc.on({}, add_recipes)
