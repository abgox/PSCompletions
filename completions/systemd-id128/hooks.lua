local function add_ids()
    for _, line in ipairs(psc.run({ "systemd-id128", "show" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "NAME" then
            psc.add({ name = name })
        end
    end
end

psc.on({ command = "show", multiple = true }, add_ids)
