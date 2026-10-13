-- starship reads $STARSHIP_CONFIG first, then <home>/.config/starship.toml on every platform
local function config_path()
    return psc.env("STARSHIP_CONFIG")
        or psc.path(psc.env("HOME") or psc.env("USERPROFILE") or "", ".config", "starship.toml")
end

-- `module --list` prints a two-line header before the module names
local function add_modules()
    for _, line in ipairs(psc.run({ "starship", "module", "--list" }) or {}) do
        local name = psc.trim(line)
        if name:match("^[%l][%w_%-]*$") then psc.add({ name = name }) end
    end
end

local configured_tip = {
    ["en-US"] = "Configured in starship.toml",
    ["zh-CN"] = "在 starship.toml 中配置"
}

-- toggle rejects a name that is not a table in the user's config
local function add_config_modules()
    local cfg = psc.toml(config_path())
    if not cfg then return end
    for name, value in pairs(cfg) do
        if type(value) == "table" then psc.add({ name = name, tip = configured_tip }) end
    end
end

local function add_profiles()
    local cfg = psc.toml(config_path())
    if cfg and cfg.profiles then
        for name, _ in pairs(cfg.profiles) do
            psc.add({ name = name, tip = configured_tip })
        end
    end
end

-- print-config emits every key with its effective value, so the tip carries it
local function add_config_keys()
    local cfg = psc.run({ "starship", "print-config" }, { format = "toml" }) or {}
    local function walk(node, prefix)
        for key, value in pairs(node) do
            local path = prefix == "" and key or prefix .. "." .. key
            if type(value) == "table" then
                psc.add({ name = path })
                -- arrays of tables ([[battery.display]]) are not key paths
                if type(next(value)) ~= "number" then walk(value, path) end
            else
                psc.add({ name = path, tip = tostring(value) })
            end
        end
    end
    walk(cfg, "")
end

psc.on({ command = "module" }, add_modules)

psc.on({ command = "toggle" }, add_config_modules)

psc.on({ option = "--profile" }, add_profiles)

psc.on({
    { command = "config" },
    { command = "print-config", multiple = true }
}, add_config_keys)
