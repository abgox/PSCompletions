local function add_pkg()
    for _, line in ipairs(psc.run({ "ya", "pkg", "list" }) or {}) do
        local t = psc.trim(line)
        if t ~= "Plugins:" and t ~= "Flavors:" then
            local repo = t:match("([^/]+/[^/]+)%s+")
            if repo then
                psc.add({ name = repo })
            end
        end
    end
end

psc.on({
    { command = { "pkg", "delete" },   multiple = true },
    { command = { "pkg", "upgrade" },  multiple = true }
}, add_pkg)
