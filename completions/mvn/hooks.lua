-- Lifecycle phases and common plugin goals live in the manifest root `next`:
-- they are a closed list known at authoring time (R-16). What remains here is
-- the pom.xml-derived plugin discovery.
local function add_local_plugins()
    -- Full coordinates only: <groupId>:<artifactId>:help. A bare artifactId is
    -- not a resolvable plugin prefix, so the old <artifactId>:help form always
    -- failed with "No plugin found for prefix". Only match inside <plugin> so
    -- dependency and project artifactIds are never offered.
    local content = psc.read("pom.xml")
    if not content then return end
    local seen = {}
    local function offer(gid, aid)
        local key = gid .. ":" .. aid
        if not seen[key] then
            seen[key] = true
            psc.add({ name = key .. ":help", tip = "local plugin" })
        end
    end
    -- <groupId> before <artifactId> (standard Maven order)
    for gid, aid in content:gmatch(
        "<plugin>%s*<groupId>%s*([^<%s]+)%s*</groupId>%s*<artifactId>%s*([^<%s]+)%s*</artifactId>"
    ) do
        offer(gid, aid)
    end
    -- <artifactId> before <groupId> (reversed, rarer)
    for aid, gid in content:gmatch(
        "<plugin>%s*<artifactId>%s*([^<%s]+)%s*</artifactId>%s*<groupId>%s*([^<%s]+)%s*</groupId>"
    ) do
        offer(gid, aid)
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

psc.on({}, add_local_plugins)

psc.on({
    { option = "--projects" },
    { option = "--resume-from" }
}, add_modules)

psc.on({ option = "--activate-profiles" }, add_profiles)

-- skipTests / maven.test.skip live in the manifest; this only adds the
-- properties declared in the current pom.xml.
psc.on({ option = "--define" }, add_properties)
