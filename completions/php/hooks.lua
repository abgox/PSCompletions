local function add_extension()
    local seen = {}
    for _, line in ipairs(psc.run({ "php", "-m" }) or {}) do
        local name = psc.trim(line)
        -- The module list repeats Zend extensions in both sections.
        if name ~= "" and not name:match("^%[") and not seen[name] then
            seen[name] = true
            psc.add({ name = name })
        end
    end
end

local function add_zend_extension()
    local in_zend = false
    for _, line in ipairs(psc.run({ "php", "-m" }) or {}) do
        local name = psc.trim(line)
        if name == "[Zend Modules]" then
            in_zend = true
        elseif name:match("^%[") then
            in_zend = false
        elseif in_zend and name ~= "" then
            psc.add({ name = name })
        end
    end
end

psc.on({
    { option = "--rextension" },
    { option = "--rextinfo" },
}, add_extension)

psc.on({ option = "--rzendextension" }, add_zend_extension)
