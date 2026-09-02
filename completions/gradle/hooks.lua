local function add_tasks()
    local lines = psc.run({ "gradle", "tasks", "--all" })
    if not lines then
        -- try wrapper
        lines = psc.run({ "./gradlew", "tasks", "--all" }) or psc.run({ "gradlew", "tasks", "--all" })
    end
    if not lines then return end
    local seen = {}
    for _, line in ipairs(lines) do
        -- task lines look like "build - Assembles and tests this project."
        local name, desc = line:match("^%s*([%w%:%-%_]+)%s+%-%s+(.+)$")
        -- also handle "  build" style without dash
        if not name then
            name = line:match("^%s*([%w%:%-%_]+)%s*$")
            desc = ""
        end
        if name and not seen[name] and not name:match("^[%-]+$") then
            -- skip headers like "Build tasks" or "----"
            if not name:match("tasks$") and #name > 1 then
                seen[name] = true
                psc.add({ name = name, tip = desc or "gradle task" })
            end
        end
    end
end

local function add_projects()
    -- parse settings.gradle / settings.gradle.kts for include statements
    local files = psc.read_batch({ "settings.gradle", "settings.gradle.kts" })
    local seen = {}
    for _, content in pairs(files) do
        if content then
            for proj in content:gmatch("include%s*%(%s*[\"']([^\"']+)[\"']") do
                local n = proj:gsub(":", "")
                if n ~= "" and not seen[n] then
                    seen[n] = true
                    psc.add({ name = proj, tip = "project" })
                end
            end
            for proj in content:gmatch("include%s+[\"']([^\"']+)[\"']") do
                local n = proj:gsub(":", "")
                if n ~= "" and not seen[n] then
                    seen[n] = true
                    psc.add({ name = proj, tip = "project" })
                end
            end
        end
    end
    -- subproject directories with build.gradle
    for _, p in ipairs(psc.glob("*/build.gradle*") or {}) do
        local dir = p:match("([^/\\]+)/build%.gradle")
        if dir and not seen[dir] then
            seen[dir] = true
            psc.add({ name = ":" .. dir, tip = p })
        end
    end
end

local function add_gradle_files()
    for _, p in ipairs(psc.glob("*.gradle*") or {}) do
        local name = p:match("([^/\\]+)$")
        if name then psc.add({ name = name, tip = p }) end
    end
    for _, p in ipairs(psc.glob("gradle/**/*") or {}) do
        local name = p:match("([^/\\]+)$")
        if name then psc.add({ name = name, tip = p }) end
    end
end

psc.on({}, function()
    add_tasks()
    add_projects()
end)

psc.on({ option = "--exclude-task" }, add_tasks)

psc.on({ option = "--init-script" }, add_gradle_files)

psc.on({ option = "--project-dir" }, function()
    local entries = psc.ls(".")
    if not entries then return end
    for _, e in ipairs(entries) do
        if e.is_dir then psc.add({ name = e.name, tip = e.path }) end
    end
end)

psc.on({ option = "--project-prop" }, function()
    local p = psc.read("gradle.properties")
    if not p then return end
    for line in p:gmatch("[^\r\n]+") do
        local k = line:match("^%s*([^#%s=]+)%s*=")
        if k then psc.add({ name = k, tip = line }) end
    end
end)
