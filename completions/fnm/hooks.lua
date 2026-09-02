local function add_versions()
    for _, line in ipairs(psc.run({ "fnm", "list" }) or {}) do
        -- fnm ls prints "* v18.19.0 default" or "v20.11.0"
        local v = line:match("(v?%d+%.%d+%.%d+)") or line:match("(v?%d+%.%d+)") or line:match("(%d+%.%d+%.%d+)")
        -- also handle alias names on the line
        local alias = line:match("%s(%S+)%s*$")
        if v then
            psc.add({ name = v, tip = line })
            -- also add without v prefix
            local bare = v:gsub("^v", "")
            if bare ~= v then psc.add({ name = bare, tip = line }) end
        elseif alias then
            psc.add({ name = alias, tip = line })
        end
    end
end

psc.on({
    { command = "use" },
    { command = "uninstall" },
    { command = "alias" },
    { command = "default" }
}, add_versions)
