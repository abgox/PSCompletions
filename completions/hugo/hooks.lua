local function add_config_files()
    psc.add(psc.items(psc.glob("hugo.{yaml,toml,json}") or {}))
    psc.add(psc.items(psc.glob("config/hugo.{yaml,toml,json}") or {}))
end

local function add_themes()
    local themes = psc.ls("themes") or {}
    for _, t in ipairs(themes) do
        if t.is_dir then
            psc.add({ name = t.name })
        end
    end
end

psc.on({ option = "--config" }, add_config_files)

psc.on({ option = "--theme" }, add_themes)
