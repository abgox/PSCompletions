local cs = {}

if psc.current.option_like then
    return completions
end

local lo = psc.opts[#psc.opts] or ""
if psc.contains({ "-Dir", "-Version", "-Segment", "-MaxConcurrency", "-TimeoutSec" }, lo) then
    return completions
end

for _, m in ipairs(psc.glob("bucket/**/*.json") or {}) do
    local name = m:match("([^/\\]+)%.json$")
    if name then
        psc.add(cs, { name = name, tip = m })
    end
end

return psc.merge(cs)
