local function list_pkg()
    local out = {}
    for _, line in ipairs(psc.run({ "ya", "pkg", "list" }) or {}) do
        local t = psc.trim(line)
        if t ~= "Plugins:" and t ~= "Flavors:" then
            local repo = t:match("([^/]+/[^/]+)%s+")
            if repo then
                table.insert(out, repo)
            end
        end
    end
    return out
end

local cs = {}

if psc.current.option_like then
    return completions
end

local cmd1, cmd2 = psc.cmds[1], psc.cmds[2]
if psc.eq(cmd1, "pkg") then
    local repos = list_pkg()
    if not cmd2 then
        if #repos > 0 then
            psc.set_symbol("delete", "switch")
            psc.set_symbol("upgrade", "switch")
        end
    elseif psc.contains({ "delete", "upgrade" }, cmd2) then
        for _, r in ipairs(repos) do
            psc.add(cs, { name = r })
        end
    end
end

return psc.merge(cs)
