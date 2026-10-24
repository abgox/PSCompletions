local function token_value(name)
    local tokens = psc.tokens or {}
    local value
    for i, t in ipairs(tokens) do
        if t.type == "option" and t.name == name and tokens[i + 1] then
            value = tokens[i + 1].input
        end
    end
    return value
end

local function add_tag()
    local seen = {}
    local path = token_value("--tag-file")
    if not path or path == "" then
        path = "tags"
    end
    for _, line in ipairs(psc.split(psc.read(path) or "", "\n")) do
        local name, file = line:match("^([^!\t][^\t]*)\t([^\t]+)")
        if name and not seen[name] then
            seen[name] = true
            psc.add({ name = name, tip = file })
        end
    end
end

psc.on({ option = "--tag" }, add_tag)
