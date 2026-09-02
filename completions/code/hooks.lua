local function add_extensions()
    for _, line in ipairs(psc.run({ "code", "--list-extensions" }) or {}) do
        local ext = psc.trim(line)
        if ext ~= "" then
            psc.add({ name = ext, tip = "extension" })
        end
    end
end

local function add_workspaces()
    for _, p in ipairs(psc.glob("*.code-workspace") or {}) do
        psc.add({ name = p, tip = "workspace" })
    end
    for _, p in ipairs(psc.glob("**/*.code-workspace") or {}) do
        psc.add({ name = p, tip = "workspace" })
    end
end

psc.on({}, add_workspaces)

psc.on({
    { option = "--install-extension" },
    { option = "--uninstall-extension" },
    { option = "--disable-extension" },
    { option = "--enable-proposed-api" }
}, add_extensions)
