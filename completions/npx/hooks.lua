local function add_bins()
    local cwd = psc.cwd or ""
    local parts = {}
    for seg in cwd:gmatch("[^/\\]+") do
        parts[#parts + 1] = seg
    end
    if #parts == 0 then
        return
    end

    local prefix = (cwd:sub(1, 1) == "/") and "/" or ""
    local dirs = {}
    for i = #parts, 1, -1 do
        dirs[#dirs + 1] = psc.path(prefix, table.concat(parts, "/", 1, i), "node_modules", ".bin")
    end

    local lists = psc.ls_batch(dirs)
    local seen = {}
    local tip = {
        ["en-US"] = "Local bin from node_modules/.bin",
        ["zh-CN"] = "node_modules/.bin 中的本地命令"
    }
    for k = 1, #dirs do
        local entries = lists[k]
        if entries then
            for _, e in ipairs(entries) do
                if not e.is_dir then
                    local base = e.name
                    local ext = base:sub(-4):lower()
                    if ext == ".cmd" or ext == ".bat" or ext == ".ps1" or ext == ".exe" then
                        base = base:sub(1, -5)
                    end
                    local key = base:lower()
                    if not seen[key] then
                        seen[key] = true
                        psc.add({ name = base, tip = tip })
                    end
                end
            end
        end
    end
end

psc.on({}, add_bins)
