local function add_themes()
    local themes = psc.ls("themes") or {}
    for _, t in ipairs(themes) do
        if t.is_dir then
            psc.add({ name = t.name })
        end
    end
end

psc.on({ option = "--theme" }, add_themes)
