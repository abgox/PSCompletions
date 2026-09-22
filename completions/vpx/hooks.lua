local function add_bins()
    -- walk up so monorepo subpackages resolve the root .bin too
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
    local tip = {
        ["en-US"] = "Local binary from node_modules/.bin",
        ["zh-CN"] = "node_modules/.bin 中的本地可执行文件"
    }
    local seen = {}
    local lists = psc.ls_batch(dirs) or {}
    for k = 1, #dirs do
        for _, e in ipairs(lists[k] or {}) do
            if not e.is_dir then
                local base = e.name
                -- strip Windows shim extensions to dedupe alias forms
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

psc.on({}, add_bins)
