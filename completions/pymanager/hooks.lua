if psc.platform ~= "windows" then
    return
end

-- tag form follows the CLI: bare for PythonCore, Company\Tag otherwise
local function tag_name(v)
    if not (v.company and v.tag) then
        return nil
    end
    if v.company == "PythonCore" then
        return v.tag
    end
    return v.company .. "\\" .. v.tag
end

local function add_tags(versions)
    for _, v in ipairs(versions) do
        local name = tag_name(v)
        if name then
            psc.add({ name = name, tip = v["display-name"] })
        end
    end
end

-- installed runtimes back uninstall targets and list filters
local function add_local_tags()
    local data = psc.run({ "pymanager", "list", "-f", "json" }, { format = "json" }) or {}
    add_tags(data.versions or {})
end

-- installable runtimes come from the online index, which needs network
local function add_online_tags()
    local data = psc.run({ "pymanager", "list", "--online", "-f", "json" }, { format = "json" }) or {}
    add_tags(data.versions or {})
end

psc.on({
    { command = "uninstall", multiple = true },
    { command = "list",      multiple = true }
}, add_local_tags)

psc.on({ command = "install", multiple = true }, add_online_tags)
