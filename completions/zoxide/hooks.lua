local cs = {}

if psc.current.option_like then
    return completions
end

local cmd1 = psc.cmds[1]
if not cmd1 then
    local probe = psc.items(psc.run({ "zoxide", "query", "--list" }) or {})
    if #probe > 0 then
        psc.set_symbol("remove", "switch")
    end
elseif psc.eq(cmd1, "remove") then
    psc.add(cs,
        psc.items(psc.run({ "zoxide", "query", "--list" }) or {},
            function(e)
                return { name = e, symbol = "stay" }
            end
        )
    )
end

return psc.merge(cs)
