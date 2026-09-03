local function add_tasks()
    -- try pixi task list --json first
    local data = psc.run({ "pixi", "task", "list", "--json" }, { format = "json" })
    if data then
        if type(data) == "table" then
            for k, v in pairs(data) do
                if type(k) == "number" and type(v) == "table" and v.name then
                    psc.add({ name = v.name, tip = v.description or "" })
                elseif type(v) == "table" and v.tasks then
                    for name, cmd in pairs(v.tasks) do
                        psc.add({ name = name, tip = type(cmd) == "string" and cmd or "" })
                    end
                elseif type(k) == "string" then
                    psc.add({ name = k, tip = type(v) == "string" and v or "" })
                end
            end
        end
        return
    end
    -- fallback to manifest parsing
    local m = psc.toml("pixi.toml")
    if not m then
        local py = psc.toml("pyproject.toml")
        if py and py.tool and py.tool.pixi then
            m = py.tool.pixi
        end
    end
    if not m then return end
    local tasks = m.tasks
    if tasks then
        for name, cmd in pairs(tasks) do
            local tip = type(cmd) == "string" and cmd or psc.join(cmd, " ")
            psc.add({ name = name, tip = tip })
        end
    end
    local features = m.feature
    if features then
        for _, feat in pairs(features) do
            if feat.tasks then
                for name, cmd in pairs(feat.tasks) do
                    local tip = type(cmd) == "string" and cmd or psc.join(cmd, " ")
                    psc.add({ name = name, tip = tip })
                end
            end
        end
    end
end

local function add_environments()
    local m = psc.toml("pixi.toml")
    if not m then
        local py = psc.toml("pyproject.toml")
        if py and py.tool and py.tool.pixi then m = py.tool.pixi end
    end
    if not m then return end
    local envs = m.environments or m.environment
    if envs then
        for name, _ in pairs(envs) do
            psc.add({ name = name, tip = "environment" })
        end
    end
    psc.add({ name = "default", tip = "default environment" })
end

local function add_features()
    local m = psc.toml("pixi.toml")
    if not m then
        local py = psc.toml("pyproject.toml")
        if py and py.tool and py.tool.pixi then m = py.tool.pixi end
    end
    if not m or not m.feature then return end
    for name, _ in pairs(m.feature) do
        psc.add({ name = name, tip = "feature" })
    end
end

local function add_platforms()
    local m = psc.toml("pixi.toml")
    if not m then
        local py = psc.toml("pyproject.toml")
        if py and py.tool and py.tool.pixi then m = py.tool.pixi end
    end
    if not m then return end
    local plats = (m.workspace and m.workspace.platforms) or (m.project and m.project.platforms) or m.platforms
    if plats then
        for _, p in ipairs(plats) do
            psc.add({ name = p, tip = "platform" })
        end
    end
end

psc.on({
    { command = "run" },
    { command = { "task", "remove" } },
    { command = { "task", "alias" }, multiple = true }
}, add_tasks)

psc.on({
    { option = "--environment" },
    { option = "-e" }
}, add_environments)

psc.on({
    { option = "--feature" },
    { option = "-f" }
}, add_features)

psc.on({
    { option = "--platform" },
    { option = "-p" }
}, add_platforms)
