local function add_projects()
    for _, line in ipairs(psc.run({ "vercel", "list" }) or {}) do
        -- vercel list shows projects like "my-app"
        local name = line:match("^(%S+)")
        if name and not name:match("^Vercel") and not name:match("^Fetching") and not name:match("^https") then
            psc.add({ name = name, tip = line })
        end
    end
end

local function add_env_keys()
    for _, line in ipairs(psc.run({ "vercel", "env", "ls" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "name" then psc.add({ name = name, tip = line }) end
    end
end

psc.on({
    { option = "--project" },
    { command = { "env", "remove" } },
    { command = { "env", "pull" } },
    { command = "alias" },
    { command = "domains" }
}, add_projects)

psc.on({ command = { "env", "remove" } }, add_env_keys)
