local function add_extensions()
    for _, line in ipairs(psc.run({ "code", "--list-extensions" }) or {}) do
        local ext = psc.trim(line)
        if ext ~= "" then
            psc.add({ name = ext, tip = "extension" })
        end
    end
end

psc.on({
    { option = "--install-extension" },
    { option = "--uninstall-extension" },
    { option = "--disable-extension" },
    { option = "--enable-proposed-api" }
}, add_extensions)
