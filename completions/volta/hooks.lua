-- Returns { bin_dir, tools_dir }; nil if not found
local function get_dirs()
    local vol = psc.env("VOLTA_HOME")
    local image = psc.path(vol, "tools", "image")
    if vol and psc.exist(image) then
        return vol, image
    end
    if psc.platform == "windows" then
        local la = psc.env("LOCALAPPDATA")
        image = psc.path(la, "Volta", "tools", "image")
        if la and psc.exist(image) then
            return psc.path(la, "Volta"), image
        end
    end
    local bin = psc.which("volta")
    if bin then
        local parent = bin:match("^(.*)[\\/][^\\/]+$")
        if parent then
            image = psc.path(parent, "tools", "image")
            if psc.exist(image) then
                return parent, image
            end
            local grand = parent:match("^(.*)[\\/][^\\/]+$")
            image = psc.path(grand, "tools", "image")
            if grand and psc.exist(image) then
                return parent, image
            end
        end
    end
end

local function add_bin_tools()
    local bin_dir = get_dirs()
    if not bin_dir then
        return
    end
    for _, e in ipairs(psc.ls(bin_dir) or {}) do
        if not e.is_dir and e.name:match("%.exe$") then
            psc.add({ name = (e.name:gsub("%.exe$", "")) })
        end
    end
end

local function add_tool_versions()
    local _, tools_dir = get_dirs()
    if not tools_dir then
        return
    end
    for _, t in ipairs(psc.ls(tools_dir) or {}) do
        if t.is_dir then
            for _, v in ipairs(psc.ls(psc.path(tools_dir, t.name)) or {}) do
                if v.is_dir then
                    psc.add({ name = t.name .. "@" .. v.name })
                end
            end
        end
    end
end

local function add_uninstallable()
    add_tool_versions()
    local _, tools_dir = get_dirs()
    local pkg = psc.path(tools_dir, "packages")
    if tools_dir and psc.exist(pkg) then
        for _, p in ipairs(psc.ls(pkg) or {}) do
            if p.is_dir then
                psc.add({ name = p.name })
            end
        end
    end
end

psc.on({ command = "which" }, add_bin_tools)

psc.on({ command = "pin" }, add_tool_versions)

psc.on({ command = "uninstall" }, add_uninstallable)
