local function add_devices()
    local lines = psc.run({ "adb", "devices" }) or {}
    for _, line in ipairs(lines) do
        if line:match("^List of devices") or line:match("^%s*$") then
            -- skip header and empty
        else
            local serial = line:match("^(%S+)")
            local state = line:match("%s+(%S+)%s*$")
            if serial then
                psc.add({ name = serial, tip = state or line })
            end
        end
    end
end

local function add_packages()
    local lines = psc.run({ "adb", "shell", "pm", "list", "packages", "--user", "0" }) or {}
    -- fallback without --user
    if #lines == 0 then
        lines = psc.run({ "adb", "shell", "pm", "list", "packages" }) or {}
    end
    for _, line in ipairs(lines) do
        local pkg = line:match("^package:(.+)$")
        if pkg then
            psc.add({ name = pkg, tip = "package --- " .. pkg })
        end
    end
end

psc.on({
    { command = "connect" },
    { command = "disconnect" },
    { command = "pair" },
    { option = "-s" },
    { option = "-t" }
}, add_devices)

psc.on({ command = "uninstall", multiple = true }, add_packages)
