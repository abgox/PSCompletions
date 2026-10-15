local function add_system_version()
    psc.add({
        name = "system",
        tip = {
            ["en-US"] = "System Python",
            ["zh-CN"] = "系统 Python",
        },
    })
end

local function add_installed_versions()
    for _, line in ipairs(psc.run({ "pyenv", "versions", "--bare" }) or {}) do
        if line ~= "" and line ~= "system" then
            psc.add({
                name = line,
                tip = {
                    ["en-US"] = "Installed Python version",
                    ["zh-CN"] = "已安装的 Python 版本",
                },
            })
        end
    end
end

local function add_known_versions()
    for _, line in ipairs(psc.run({ "python-build", "--definitions" }) or {}) do
        if line ~= "" then
            psc.add({
                name = line,
                tip = {
                    ["en-US"] = "Installable Python version",
                    ["zh-CN"] = "可安装的 Python 版本",
                },
            })
        end
    end
end

local function add_shims()
    for _, line in ipairs(psc.run({ "pyenv", "shims", "--short" }) or {}) do
        if line ~= "" then
            psc.add({
                name = line,
                tip = {
                    ["en-US"] = "Pyenv shim",
                    ["zh-CN"] = "Pyenv shim 可执行文件",
                },
            })
        end
    end
end

local function add_hook_commands()
    for _, line in ipairs(psc.run({ "pyenv", "hooks", "--complete" }) or {}) do
        if line ~= "" then
            psc.add({
                name = line,
                tip = {
                    ["en-US"] = "Command with hook scripts",
                    ["zh-CN"] = "带 hook 脚本的命令",
                },
            })
        end
    end
end

-- `system` is offered only where upstream echoes it (uninstall/latest do not)
psc.on({
    { command = "global", multiple = true },
    { command = "local",  multiple = true },
    { command = "shell",  multiple = true },
    { command = "prefix", multiple = true },
}, add_system_version)

-- installed versions fill every version-name slot
psc.on({
    { command = "global",    multiple = true },
    { command = "local",     multiple = true },
    { command = "shell",     multiple = true },
    { command = "prefix",    multiple = true },
    { command = "uninstall", multiple = true },
    { command = "latest" },
}, add_installed_versions)

-- `latest --known` resolves against definitions instead of installed versions
psc.on({ command = "latest", option = "--known" }, add_known_versions)

-- `install` takes one or more definitions from python-build
psc.on({ command = "install", multiple = true }, add_known_versions)

-- first positional only: anything after it is the program's own argument
psc.on({
    { command = "exec" },
    { command = "which" },
    { command = "whence" },
}, add_shims)

psc.on({ command = "hooks" }, add_hook_commands)

-- `help`/`completions` take the tool's own commands (rejected when bogus)
psc.on({
    { command = "help" },
    { command = "completions" },
}, function()
    psc.add(psc.mount_items({ "next" }))
end)
