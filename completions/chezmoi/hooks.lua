local function add_managed()
    for _, line in ipairs(psc.run({ "chezmoi", "managed" }) or {}) do
        local f = psc.trim(line)
        if f ~= "" then
            psc.add({ name = f, tip = "managed" })
        end
    end
end

local function add_status()
    for _, line in ipairs(psc.run({ "chezmoi", "status" }) or {}) do
        -- status lines: " M ~/.gitconfig" -> last field is target
        local f = line:match("%s(%S+)%s*$") or line:match("(%S+)%s*$")
        f = psc.trim(f or "")
        if f ~= "" and f ~= "status" then
            psc.add({ name = f, tip = line })
        end
    end
end

local function add_data_keys()
    local data = psc.run({ "chezmoi", "data", "--format", "json" }, { format = "json" })
    if data and type(data) == "table" then
        for k, _ in pairs(data) do
            psc.add({ name = k, tip = "data key" })
        end
        -- nested chezmoi key is common
        if data.chezmoi and type(data.chezmoi) == "table" then
            for k, _ in pairs(data.chezmoi) do
                psc.add({ name = "chezmoi." .. k, tip = "chezmoi data" })
            end
        end
    end
end

local function add_targets()
    -- prefer managed, fallback to status
    local before = #completions
    add_managed()
    if #completions == before then
        add_status()
    end
end

psc.on({
    { command = "add",         multiple = true },
    { command = "apply",       multiple = true },
    { command = "cat",         multiple = true },
    { command = "chattr",      multiple = true },
    { command = "destroy",     multiple = true },
    { command = "diff",        multiple = true },
    { command = "dump",        multiple = true },
    { command = "edit",        multiple = true },
    { command = "forget",      multiple = true },
    { command = "merge",       multiple = true },
    { command = "merge-all",   multiple = true },
    { command = "re-add",      multiple = true },
    { command = "source-path", multiple = true },
    { command = "target-path", multiple = true },
    { command = "status",      multiple = true },
    { command = "verify",      multiple = true },
    { command = "ignored" },
    { command = "unmanaged" }
}, add_targets)

psc.on({
    { command = "data" },
    { command = "execute-template", multiple = true }
}, add_data_keys)

psc.on({ command = "chattr" }, add_managed)
