local function add_plugins()
    for _, line in ipairs(psc.run({ "packer", "plugins", "installed" }) or {}) do
        local name = line:match("^(%S+)")
        -- skip header like "Installed plugins:"
        if name and not name:match("^Installed") and not name:match("^%*") then
            -- plugin ids look like github.com/hashicorp/amazon
            if name:find("%.") or name:find("/") then
                psc.add({ name = name, tip = line })
            else
                -- fallback: still add raw token
                if name ~= "" then psc.add({ name = name, tip = line }) end
            end
        end
    end
end

psc.on({
    { command = { "plugins", "remove" }, multiple = true },
    { command = { "plugins", "install" } }
}, add_plugins)
