local function add_sessions()
    for _, line in ipairs(psc.run({ "zellij", "list-sessions" }) or {}) do
        -- output: "my-session [Created ...]"
        local name = line:match("^(%S+)")
        if name and name ~= "No" then
            psc.add({ name = name, tip = line })
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
