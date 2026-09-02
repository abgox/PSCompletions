local function add_snapshots()
    local data = psc.run({ "restic", "snapshots", "--json" }, { format = "json" })
    if data and type(data) == "table" then
        for _, s in ipairs(data) do
            local id = s.short_id or s.id
            if id then
                local tip = ""
                if s.time then tip = s.time end
                if s.hostname then tip = tip .. " host:" .. s.hostname end
                if s.tags and type(s.tags) == "table" and next(s.tags) then
                    tip = tip .. " tags:" .. psc.join(s.tags, ",")
                end
                if s.paths and type(s.paths) == "table" then
                    tip = tip .. " " .. psc.join(s.paths, " ")
                end
                psc.add({ name = id, tip = psc.trim(tip) })
                if s.id and s.id ~= id then
                    psc.add({ name = s.id, tip = tip })
                end
            end
        end
        return
    end
    for _, line in ipairs(psc.run({ "restic", "snapshots" }) or {}) do
        local id = line:match("^(%x+)")
        if id then psc.add({ name = id, tip = line }) end
    end
end

local function add_tags()
    local data = psc.run({ "restic", "snapshots", "--json" }, { format = "json" })
    if data then
        local seen = {}
        for _, s in ipairs(data) do
            if s.tags then
                for _, t in ipairs(s.tags) do
                    if not seen[t] then
                        seen[t] = true
                        psc.add({ name = t, tip = "tag" })
                    end
                end
            end
        end
    end
end

psc.on({
    { command = "snapshots", multiple = true },
    { command = "restore", multiple = true },
    { command = "ls", multiple = true },
    { command = "dump", multiple = true },
    { command = "diff", multiple = true },
    { command = "tag", multiple = true },
    { command = "forget", multiple = true },
    { command = "copy", multiple = true },
    { option = "--parent" }
}, add_snapshots)

psc.on({
    { option = "--tag" },
    { option = "--keep-tag" }
}, add_tags)
