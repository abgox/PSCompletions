local function add_files()
    for _, p in ipairs(psc.glob("*.{yml,yaml,json,toml}") or {}) do
        psc.add({ name = p, tip = "data" })
    end
end

psc.on({
    { command = "eval" },
    { command = "eval-all" },
    { option = "--from-file" },
    { option = "--split-exp-file" },
    {}
}, add_files)
