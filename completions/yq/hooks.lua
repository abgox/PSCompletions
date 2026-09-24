local function add_files()
    for _, p in ipairs(psc.glob("*.{yml,yaml,json,toml}") or {}) do
        psc.add({ name = p, tip = "data" })
    end
end

psc.on({
    { option = "--from-file" },
    { option = "--split-exp-file" },
}, add_files)
