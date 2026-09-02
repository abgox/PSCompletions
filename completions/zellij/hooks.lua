local function add_sessions()
    for _, line in ipairs(psc.run({ "zellij", "list-sessions" }) or {}) do
        -- output: "my-session [Created ...]"
        local name = line:match("^(%S+)")
        if name and name ~= "No" then
            psc.add({ name = name, tip = line })
        end
    end
end

local function add_layouts()
    for _, p in ipairs(psc.glob("*.kdl") or {}) do
        psc.add({ name = p, tip = "layout" })
    end
    -- layout dir from config
    local layout_dir = psc.env("ZELLIJ_CONFIG_DIR")
    if layout_dir then
        for _, e in ipairs(psc.ls(layout_dir) or {}) do
            if not e.is_dir then psc.add({ name = e.name, tip = e.path }) end
        end
    end
end

psc.on({
    { command = "attach" },
    { command = "delete-session" },
    { command = "kill-session" },
    { command = "watch" },
    { option = "--session" }
}, add_sessions)

psc.on({
    { option = "--layout" },
    { option = "--new-session-with-layout" }
}, add_layouts)
