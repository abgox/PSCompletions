local function add_db_files()
    for _, p in ipairs(psc.glob("*.{db,sqlite,sqlite3}") or {}) do
        psc.add({ name = p, tip = "database" })
    end
end

psc.on({
    {},
    { option = "-init" },
    { option = "-append" }
}, add_db_files)
