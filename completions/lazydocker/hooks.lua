local function add_files()
    for _, p in ipairs(psc.glob("docker-compose*.{yml,yaml}") or {}) do
        psc.add({ name = p, tip = "compose" })
    end
    for _, p in ipairs(psc.glob("compose*.{yml,yaml}") or {}) do
        psc.add({ name = p, tip = "compose" })
    end
end

psc.on({ option = "--file" }, add_files)
