local function add_filters()
    -- common jq filters
    local filters = { ".", ".[]", "keys", "keys_unsorted", "values", "length", "type", "select", "map", "select(.a)" }
    for _, f in ipairs(filters) do psc.add({ name = f, tip = "filter" }) end
    -- try to read keys from a json file given as earlier arg
    local json_arg
    for _, tok in ipairs(psc.tokens) do
        if tok.type == "value" and tok.input:match("%.json$") then
            json_arg = tok.input
            break
        end
    end
    if json_arg then
        local data = psc.json(json_arg)
        if data and type(data) == "table" then
            for k, _ in pairs(data) do
                if k and k ~= "" then
                    psc.add({ name = "." .. k, tip = "key " .. k })
                    psc.add({ name = '."' .. k .. '"', tip = "key " .. k })
                end
            end
        end
    end
end

psc.on({}, add_filters)
