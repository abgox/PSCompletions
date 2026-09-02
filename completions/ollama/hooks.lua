local function add_models()
    local lines = psc.run({ "ollama", "list" }) or {}
    for i, l in ipairs(lines) do
        if i == 1 and l:match("^NAME") then
            -- skip header
        else
            local name = l:match("^(%S+)")
            if name and name ~= "" then
                psc.add({ name = name, tip = l })
            end
        end
    end
end

local function add_running()
    local lines = psc.run({ "ollama", "ps" }) or {}
    for i, l in ipairs(lines) do
        if i == 1 and l:match("^NAME") then
            -- skip header
        else
            local name = l:match("^(%S+)")
            if name and name ~= "" then
                psc.add({ name = name, tip = l })
            end
        end
    end
end

psc.on({
    { command = "show" },
    { command = "run" },
    { command = "rm", multiple = true },
    { command = "cp", multiple = true },
    { command = "push" },
    { command = "pull" },
    { command = "create" },
    { command = "show", multiple = true },
    { command = "stop", multiple = true },
    { option = "--model" },
    { command = "cp" }
}, add_models)

psc.on({ command = "stop" }, add_running)
