local function add_modules()
    for _, line in ipairs(psc.run({ "go", "list", "-m", "all" }) or {}) do
        local m = psc.trim(line)
        if m ~= "" then
            psc.add({ name = m, tip = "module" })
        end
    end
end

local function add_local_packages()
    for _, line in ipairs(psc.run({ "go", "list", "./..." }) or {}) do
        local pkg = psc.trim(line)
        if pkg ~= "" then
            psc.add({ name = pkg, tip = "package" })
        end
    end
end

local function add_all_packages()
    for _, line in ipairs(psc.run({ "go", "list", "all" }) or {}) do
        local pkg = psc.trim(line)
        if pkg ~= "" then
            psc.add({ name = pkg, tip = "package" })
        end
    end
end

psc.on({
    { command = "get", multiple = true },
    { command = "install", multiple = true },
    { command = { "mod", "download" }, multiple = true },
    { command = { "mod", "why" }, multiple = true },
    { command = "list", multiple = true }
}, add_modules)

psc.on({
    { command = "build", multiple = true },
    { command = "run", multiple = true },
    { command = "test", multiple = true },
    { command = "vet", multiple = true },
    { command = "fmt", multiple = true },
    { command = "generate", multiple = true },
    { command = "install", multiple = true }
}, add_local_packages)

psc.on({
    { command = "list" },
    { command = "doc" }
}, add_all_packages)

psc.on({ command = "env" }, function()
    for _, line in ipairs(psc.run({ "go", "env" }) or {}) do
        local k = line:match("^([^=]+)=")
        if k then psc.add({ name = k, tip = line }) end
    end
end)

psc.on({ command = "tool" }, function()
    for _, line in ipairs(psc.run({ "go", "tool" }) or {}) do
        local name = line:match("^(%S+)")
        if name and name ~= "tool" then
            psc.add({ name = name, tip = line })
        end
    end
end)
