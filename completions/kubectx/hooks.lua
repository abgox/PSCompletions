local function kubeconfig_path()
    local kc = psc.env("KUBECONFIG")
    if kc then
        return kc:match("^[^;]+")
    end
    local home = psc.env("USERPROFILE") or psc.env("HOME")
    if home then
        return home .. "/.kube/config"
    end
end

local function contexts()
    local path = kubeconfig_path()
    if not path or not psc.exist(path) then
        return {}
    end
    local cfg = psc.yaml(path)
    local out = {}
    if cfg and type(cfg.contexts) == "table" then
        for _, c in ipairs(cfg.contexts) do
            if c and c.name then
                out[#out + 1] = c.name
            end
        end
    end
    return out
end

if psc.current.option_like then
    return completions
end

local cs = {}
local last = psc.tokens[#psc.tokens]

if last and psc.contains({ "--current", "--unset" }, last.name) then
    return completions
end

local multi = last and psc.eq(last.name, "--delete")
for _, name in ipairs(contexts()) do
    psc.add(cs, { name = name, symbol = multi and "stay" or nil })
end

return psc.merge(cs)
