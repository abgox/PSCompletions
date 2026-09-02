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

local function add_templates()
    for _, p in ipairs(psc.glob("*.pkr.hcl") or {}) do
        psc.add({ name = p, tip = "template" })
    end
    for _, p in ipairs(psc.glob("*.pkr.json") or {}) do
        psc.add({ name = p, tip = "template" })
    end
    for _, p in ipairs(psc.glob("*.json") or {}) do
        psc.add({ name = p, tip = "template" })
    end
end

psc.on({
    { command = { "plugins", "remove" }, multiple = true },
    { command = { "plugins", "install" } }
}, add_plugins)

psc.on({
    { command = "build", multiple = true },
    { command = "console" },
    { command = "fix" },
    { command = "fmt", multiple = true },
    { command = "hcl2_upgrade" },
    { command = "init", multiple = true },
    { command = "inspect", multiple = true },
    { command = "validate", multiple = true },
    { command = "verify-attestation" },
    { command = { "plugins", "required" } }
}, add_templates)

psc.on({ option = "-var-file" }, function()
    for _, p in ipairs(psc.glob("*.pkrvars.hcl") or {}) do
        psc.add({ name = p, tip = "var file" })
    end
    for _, p in ipairs(psc.glob("*.auto.pkrvars.hcl") or {}) do
        psc.add({ name = p, tip = "var file" })
    end
end)
