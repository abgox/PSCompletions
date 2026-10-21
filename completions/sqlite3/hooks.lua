local function add_vfs()
    for _, line in ipairs(psc.run({ "sqlite3", ":memory:", ".vfslist" }) or {}) do
        local name = line:match('vfs%.zName%s*=%s*"(.-)"')
        if name then
            psc.add({ name = name, tip = "vfs --- " .. name })
        end
    end
end

psc.on({ option = "-vfs" }, add_vfs)
