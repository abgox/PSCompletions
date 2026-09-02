local function add_installed()
    local lines = psc.run({ "winget", "list", "--accept-source-agreements" }) or {}
    for _, line in ipairs(lines) do
        -- skip header separator
        if not line:match("^%-") and not line:match("^Name") and #psc.trim(line) > 0 then
            -- local id = line:match("^(%S+)%s+")
            -- winget list columns: Name Id Version ...
            -- id is second column, try to extract
            local parts = {}
            for p in line:gmatch("%S+") do parts[#parts + 1] = p end
            if #parts >= 2 then
                psc.add({ name = parts[2], tip = line })
            end
        end
    end
end

local function add_search()
    -- not called without query; provide installed as fallback
    add_installed()
end

psc.on({
    { command = "uninstall", multiple = true },
    { command = "upgrade",   multiple = true },
    { command = "show" },
    { command = "pin",       multiple = true }
}, add_installed)

psc.on({
    { command = "install", multiple = true },
    { command = "search" }
}, add_search)
