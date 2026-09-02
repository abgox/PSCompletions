if psc.typing.option_like then
    return
end

if #psc.tokens ~= 0 and psc.contains({ "-Dir", "-Version", "-Segment", "-MaxConcurrency", "-TimeoutSec" }, psc.tokens[#psc.tokens].name) then
    return
end

local function add_manifests()
    for _, m in ipairs(psc.glob("bucket/**/*.json") or {}) do
        local name = m:match("([^/\\]+)%.json$")
        if name then
            psc.add({ name = name, tip = m })
        end
    end
end

psc.on({}, add_manifests)
