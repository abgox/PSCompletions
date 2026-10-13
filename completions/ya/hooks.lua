local function add_pkg()
    -- section headers ("Plugins:", "Flavors:") also name the package category
    local kind = "Package"
    for _, line in ipairs(psc.run({ "ya", "pkg", "list" }) or {}) do
        local t = psc.trim(line)
        if t:match("^%S+:$") then
            kind = t:sub(1, -2)
        else
            local repo, hash = t:match("^(%S+) %((%x+)%)")
            if repo and repo:find("/") then
                psc.add({ name = repo, tip = kind .. " " .. hash })
            end
        end
    end
end

psc.on({
    { command = { "pkg", "delete" },  multiple = true },
    { command = { "pkg", "upgrade" }, multiple = true }
}, add_pkg)
