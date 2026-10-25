local function benchmark_path()
    for i, token in ipairs(psc.tokens) do
        if token.type == "option" and psc.eq(token.name, "--benchmark") then
            local value = psc.tokens[i + 1]
            if value and value.type == "value" then
                return value.input
            end
            return
        end
    end
end

local function add_tags()
    local benchmark = benchmark_path()
    if not benchmark then
        return
    end
    -- Tags are defined in the benchmark file, so the CLI's own listing is the only source.
    for _, line in ipairs(psc.run({ "drill", "--benchmark", benchmark, "--list-tags" }) or {}) do
        for tag in line:gmatch('"([^"]+)"') do
            psc.add({ name = tag })
        end
    end
end

psc.on({
    { option = "--tags" },
    { option = "--skip-tags" }
}, add_tags)
