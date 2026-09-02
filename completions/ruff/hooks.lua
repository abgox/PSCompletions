local function add_files()
    for _, p in ipairs(psc.glob("**/*.py") or {}) do psc.add({ name = p }) end
end

local function add_config()
    for _, p in ipairs(psc.glob("{ruff.toml,.ruff.toml,pyproject.toml}") or {}) do psc.add({ name = p }) end
end

psc.on({
    {},
    { option = "--config" }
}, add_config)

psc.on({
    {},
    { command = "check" },
    { command = "format" },
    { command = "analyze" },
    { command = "rule" },
    { command = "linter" }
}, add_files)

psc.on({ option = "--select" }, function()
    -- common ruff rule prefixes
    for _, r in ipairs({ "E", "F", "W", "C", "N", "UP", "S", "B", "A", "COM", "DTZ", "TCH", "TID", "Q", "RUF", "FLY", "I" }) do
        psc.add({ name = r })
    end
end)
