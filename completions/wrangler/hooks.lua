local function add_workers()
    for _, line in ipairs(psc.run({ "wrangler", "deployments", "list" }) or {}) do
        local name = line:match("^(%S+)")
        if name then psc.add({ name = name, tip = line }) end
    end
end

psc.on({ option = "--env" }, function()
    -- parse wrangler.toml for envs
    local txt = psc.read("wrangler.toml")
    if txt then
        for env in txt:gmatch("%[env%.([%w%-_]+)%]") do
            psc.add({ name = env, tip = "env" })
        end
    end
end)

psc.on({
    { command = "tail" },
    { command = "rollback" }
}, add_workers)
