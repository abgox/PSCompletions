local function get_config_path()
    local kc = psc.env("KUBECONFIG")
    if kc then
        return kc:match("^[^;]+")
    end
    local home = psc.env("USERPROFILE") or psc.env("HOME")
    if home then
        return psc.path(home, ".kube", "config")
    end
end

local function add_contexts()
    local path = get_config_path()
    if path and psc.exist(path) then
        local cfg = psc.yaml(path)
        if cfg and type(cfg.contexts) == "table" then
            for _, c in ipairs(cfg.contexts) do
                if c and c.name then
                    psc.add({ name = c.name })
                end
            end
        end
    end
end

psc.on({
    {},
    { option = "--delete" },
    { option = "--shell" },
    { option = "--readonly" }
}, add_contexts)
