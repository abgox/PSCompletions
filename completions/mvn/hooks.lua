local lifecycle_phases = {
    "clean", "validate", "compile", "test", "package", "verify", "install", "site", "deploy",
    "pre-clean", "post-clean", "pre-site", "post-site", "site-deploy"
}

local common_goals = {
    "compiler:compile", "compiler:testCompile", "surefire:test", "failsafe:integration-test",
    "jar:jar", "war:war", "shade:shade", "exec:java", "exec:exec",
    "dependency:tree", "dependency:resolve", "help:describe", "help:effective-pom"
}

local function add_phases_and_goals()
    for _, n in ipairs(lifecycle_phases) do
        psc.add({ name = n, tip = "lifecycle phase" })
    end
    for _, n in ipairs(common_goals) do
        psc.add({ name = n, tip = "plugin goal" })
    end
    -- discover local plugin goals via pom if present
    local content = psc.read("pom.xml")
    if content then
        for plugin in content:gmatch("<artifactId>%s*([^<%s]+)%s*</artifactId>") do
            local goal = plugin .. ":help"
            psc.add({ name = goal, tip = "local plugin" })
        end
    end
end

local function add_modules()
    local content = psc.read("pom.xml")
    if not content then return end
    for mod in content:gmatch("<module>%s*([^<%s]+)%s*</module>") do
        psc.add({ name = mod, tip = "module" })
    end
end

local function add_profiles()
    local content = psc.read("pom.xml")
    if not content then return end
    for id in content:gmatch("<profile>%s*<id>%s*([^<%s]+)%s*</id>") do
        psc.add({ name = id, tip = "profile" })
    end
end

local function add_properties()
    local content = psc.read("pom.xml")
    if not content then return end
    for k in content:gmatch("<properties>%s*(.-)%s*</properties>") do
        for prop in k:gmatch("<([^>/]+)>") do
            if not prop:match("^/") and prop ~= "properties" then
                psc.add({ name = prop, tip = "property" })
            end
        end
    end
end

psc.on({}, add_phases_and_goals)

psc.on({
    { option = "--projects" },
    { option = "--resume-from" }
}, add_modules)

psc.on({ option = "--activate-profiles" }, add_profiles)

psc.on({ option = "--define" }, function()
    add_properties()
    -- also add common defines
    psc.add({ name = "skipTests", tip = "skip tests" })
    psc.add({ name = "maven.test.skip", tip = "skip test compile" })
end)

psc.on({ option = "--file" }, function()
    for _, p in ipairs(psc.glob("**/pom.xml") or {}) do
        local name = p:match("([^/\\]+)$")
        if name then psc.add({ name = p, tip = p }) end
    end
    psc.add({ name = "pom.xml", tip = "main pom" })
end)
