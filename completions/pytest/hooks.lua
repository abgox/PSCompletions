local function add_config()
    local patterns = { "pytest.ini", "pytest.toml", "tox.ini", "setup.cfg", "pyproject.toml" }
    for _, pat in ipairs(patterns) do
        for _, p in ipairs(psc.glob(pat) or {}) do psc.add({ name = p }) end
    end
end

psc.on({ option = "--config-file" }, add_config)
