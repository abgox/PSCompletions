local function add_system_version()
    psc.add({
        name = "system",
        tip = {
            ["en-US"] = "System Ruby",
            ["zh-CN"] = "系统 Ruby",
        },
    })
end

local function add_installed_versions()
    for _, name in ipairs(psc.run({ "rbenv", "versions", "--bare" }) or {}) do
        if name ~= "" and name ~= "system" then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = "Installed Ruby version",
                    ["zh-CN"] = "已安装的 Ruby 版本",
                },
            })
        end
    end
end

local function add_known_versions()
    for _, name in ipairs(psc.run({ "rbenv", "install", "--list-all" }) or {}) do
        if name ~= "" then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = "Installable Ruby definition",
                    ["zh-CN"] = "可安装的 Ruby 定义",
                },
            })
        end
    end
end

local function add_shims()
    for _, name in ipairs(psc.run({ "rbenv", "shims", "--short" }) or {}) do
        if name ~= "" then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = "rbenv shim",
                    ["zh-CN"] = "rbenv shim 可执行文件",
                },
            })
        end
    end
end

-- `system` is offered only where rbenv's own completions echo it
psc.on({
    { command = "global" },
    { command = "local" },
    { command = "prefix" },
    { command = "shell" },
}, add_system_version)

psc.on({
    { command = "global" },
    { command = "local" },
    { command = "prefix" },
    { command = "shell" },
    { command = "uninstall" },
}, add_installed_versions)

psc.on({ command = "install" }, add_known_versions)

-- shims are the executables these commands resolve
psc.on({
    { command = "exec" },
    { command = "whence" },
    { command = "which" },
}, add_shims)

psc.on({
    { command = "completions" },
    { command = "help" },
}, function()
    psc.add(psc.mount_items({ "next" }))
end)
