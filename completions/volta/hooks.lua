-- Returns { bin_dir, tools_dir }; nil if not found
local function find_dirs()
    local vol = psc.env("VOLTA_HOME")
    if vol and psc.exist(vol .. "/tools/image") then
        return vol, vol .. "/tools/image"
    end
    local la = psc.env("LOCALAPPDATA")
    if la and psc.exist(la .. "/Volta/tools/image") then
        return la .. "/Volta", la .. "/Volta/tools/image"
    end
    -- Try to derive from the volta executable location
    for _, line in ipairs(psc.run({ "where", "volta" }) or {}) do
        local bin = psc.trim(line)
        if bin ~= "" then
            local parent = bin:match("^(.*)[\\/][^\\/]+$")
            if parent then
                if psc.exist(parent .. "/tools/image") then
                    return parent, parent .. "/tools/image"
                end
                local grand = parent:match("^(.*)[\\/][^\\/]+$")
                if grand and psc.exist(grand .. "/tools/image") then
                    return parent, grand .. "/tools/image"
                end
            end
        end
    end
    return nil
end

local cs = {}

if psc.current.option_like then
    return completions
end

local cmd1 = psc.cmds[1]
local bin_dir, tools_dir = find_dirs()

if not bin_dir or not tools_dir then
    return completions
end

if not cmd1 then
    for _, e in ipairs(psc.ls(bin_dir) or {}) do
        if not e.is_dir and e.name:match("%.exe$") then
            psc.set_symbol("which", "switch")
            break
        end
    end
    for _, t in ipairs(psc.ls(tools_dir) or {}) do
        if t.is_dir then
            psc.set_symbol("pin", "switch")
            psc.set_symbol("uninstall", "switch")
            break
        end
    end
    return completions
end

if not psc.contains({ "pin", "uninstall", "which" }, cmd1) then
    return completions
end

if psc.eq(cmd1, "which") then
    for _, e in ipairs(psc.ls(bin_dir) or {}) do
        if not e.is_dir and e.name:match("%.exe$") then
            psc.add(cs, { name = (e.name:gsub("%.exe$", "")) })
        end
    end
else
    for _, t in ipairs(psc.ls(tools_dir) or {}) do
        if t.is_dir then
            for _, v in ipairs(psc.ls(tools_dir .. "/" .. t.name) or {}) do
                if v.is_dir then
                    psc.add(cs, { name = t.name .. "@" .. v.name })
                end
            end
        end
    end
    if psc.eq(cmd1, "uninstall") and psc.exist(tools_dir .. "/packages") then
        for _, p in ipairs(psc.ls(tools_dir .. "/packages") or {}) do
            if p.is_dir then
                psc.add(cs, { name = p.name })
            end
        end
    end
end

return psc.merge(cs)
