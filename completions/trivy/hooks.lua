local function add_config()
    for _, p in ipairs(psc.glob("{trivy.yaml,trivy.yml,trivy-default.yaml}") or {}) do psc.add({ name = p }) end
end

local function add_ignore()
    for _, p in ipairs(psc.glob(".trivyignore") or {}) do psc.add({ name = p }) end
end

local function add_secret_config()
    for _, p in ipairs(psc.glob("trivy-secret.yaml") or {}) do psc.add({ name = p }) end
end

psc.on({ option = "--config" }, add_config)

psc.on({ option = "--ignorefile" }, add_ignore)

psc.on({ option = "--secret-config" }, add_secret_config)
