local cs = {}

if psc.current.option_like then
    return completions
end

local cmd1, cmd2 = psc.cmds[1], psc.cmds[2]
if psc.contains({ "default", "uninstall", "run" }, cmd1) then
    psc.add(cs, psc.items(psc.run({ "rustup", "toolchain", "list", "-q" }) or {}))
elseif psc.eq(cmd1, "override") and psc.eq(cmd2, "set") then
    psc.add(cs, psc.items(psc.run({ "rustup", "toolchain", "list", "-q" }) or {}))
elseif psc.eq(cmd1, "toolchain") and psc.contains({ "install", "uninstall" }, cmd2) then
    psc.add(cs, psc.items(psc.run({ "rustup", "toolchain", "list", "-q" }) or {}))
elseif psc.eq(cmd1, "target") then
    if psc.eq(cmd2, "add") then
        psc.add(cs, psc.items(psc.run({ "rustup", "target", "list", "-q" }) or {}))
    elseif psc.eq(cmd2, "remove") then
        psc.add(cs, psc.items(psc.run({ "rustup", "target", "list", "--installed", "-q" }) or {}))
    end
elseif psc.eq(cmd1, "component") then
    if psc.eq(cmd2, "add") then
        psc.add(cs, psc.items(psc.run({ "rustup", "component", "list", "-q" }) or {}))
    elseif psc.eq(cmd2, "remove") then
        psc.add(cs, psc.items(psc.run({ "rustup", "component", "list", "--installed", "-q" }) or {}))
    end
end

return psc.merge(cs)
