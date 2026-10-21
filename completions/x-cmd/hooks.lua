local function add_env_packages()
    for _, line in ipairs(psc.run({ "x-cmd", "env", "ls" }) or {}) do
        local name = line:match("^(%S+)")
        if name then
            psc.add({ name = name, tip = "package --- " .. name })
        end
    end
end

psc.on({
    { command = { "env", "use" },  multiple = true },
    { command = { "env", "try" },  multiple = true },
    { command = { "env", "unuse" }, multiple = true },
    { command = { "env", "ls" },   multiple = true }
}, add_env_packages)

local function add_uninstall()
    local managers = { "brew", "scoop", "apt", "dnf", "apk", "pacman", "pixi", "xpkg" }
    local args = {}
    local in_uninstall, in_rm = false, false
    for _, token in ipairs(psc.tokens) do
        if token.type == "command" and token.name == "uninstall" then
            in_uninstall = true
        elseif in_uninstall and token.type == "command" and token.name == "rm" then
            in_rm = true
        elseif in_rm then
            args[#args + 1] = token.name
        end
    end
    if #args == 0 then
        for _, manager in ipairs(managers) do
            psc.add({ name = manager, tip = "manager --- " .. manager })
        end
        return
    end
    local manager = args[1]
    for _, line in ipairs(psc.run({ "x-cmd", "uninstall", "ls" }) or {}) do
        local name, owner = line:match("^(%S+)%s+(%S+)")
        if name and owner == manager then
            psc.add({ name = name, tip = manager })
        end
    end
end

psc.on({ command = { "uninstall", "rm" }, multiple = true }, add_uninstall)

