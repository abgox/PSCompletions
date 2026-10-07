local function add_fonts()
    for _, line in ipairs(psc.run({ "typst", "fonts" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" then psc.add({ name = name, tip = "font" }) end
    end
end

local function add_packages()
    -- local package cache
    local cache = psc.env("TYPST_PACKAGE_CACHE") or
        psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".cache", "typst", "packages")
    for _, e in ipairs(psc.ls(cache) or {}) do
        psc.add({ name = e.name, tip = e.path })
    end
end

psc.on({ command = "fonts" }, add_fonts)

psc.on({ command = "init" }, add_packages)
