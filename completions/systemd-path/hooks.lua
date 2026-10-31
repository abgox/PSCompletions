local function add_path_names()
    for _, line in ipairs(psc.run({ "systemd-path" }) or {}) do
        local name = line:match("^(%S+):")
        if name then
            psc.add({ name = name })
        end
    end
end

psc.on({ multiple = true }, add_path_names)
