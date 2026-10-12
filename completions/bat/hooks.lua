-- --list-languages prints "Name:ext,...", the name is the completable value
local function add_languages()
    for _, line in ipairs(psc.run({ "bat", "--list-languages" }) or {}) do
        local name = psc.trim(line:match("^([^:]+)") or "")
        if name ~= "" then
            psc.add({ name = name })
        end
    end
end

local function add_themes()
    psc.add(psc.items(psc.run({ "bat", "--list-themes" }) or {}))
end

psc.on({ option = "--language" }, add_languages)

psc.on({
    { option = "--theme" },
    { option = "--theme-dark" },
    { option = "--theme-light" }
}, add_themes)
