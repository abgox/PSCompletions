local BOOKMARK_TEMPLATE = [[if(remote,
  if(tracked,
separate(" ",
  label("bookmark", name ++ "@" ++ remote),
),
label("bookmark", name ++ "@" ++ remote),
  ),
  label("bookmark", name)
) ++ "\n"
]]

local function add_bookmark(cs)
    psc.add(cs,
        psc.items(psc.run({ "jj", "bookmark", "list", "--all-remotes", "--template", BOOKMARK_TEMPLATE }) or {},
            function(name)
                return { name = name, tip = "bookmark --- " .. name }
            end))
end

local function add_tag(cs)
    psc.add(cs, psc.items(psc.run({ "jj", "tag", "list", "--template", BOOKMARK_TEMPLATE }) or {}, function(name)
        return { name = name, tip = "tag --- " .. name }
    end))
end

local function add_common_revsets(cs)
    local sets = { "'..'", "'::'", "'@'", "'@-'", "'@+'", "'all()'" }
    for _, s in ipairs(sets) do
        psc.add(cs, { name = s, tip = "revsets --- " .. s })
    end
end

local function add_revsets(cs)
    for _, line in ipairs(psc.run({
        "jj", "log",
        "-r", "present(@) | present(trunk()) | ancestors(immutable_heads().., 2)",
        "-T", 'change_id.short() ++ ": " ++ description.first_line() ++ "\\n"',
        "--no-pager", "--no-graph", "--limit", "30",
    }) or {}) do
        local part0, part1 = line:match("^([^:]+):%s*(.*)$")
        if part0 then
            local tip = part1
            if tip == nil or tip == "" then
                tip = "(no description set)"
            end
            psc.add(cs, { name = part0, tip = tip })
        end
    end
end

local function add_remote(cs)
    for _, line in ipairs(psc.run({ "jj", "git", "remote", "list" }) or {}) do
        local name, url = line:match("^(%S+)%s+(.*)$")
        if name then
            psc.add(cs, { name = name, tip = url })
        end
    end
end

local cs = {}

if psc.current.option_like then
    return completions
end

local cmd1, cmd2, cmd3 = psc.cmds[1], psc.cmds[2], psc.cmds[3]

if not cmd1 then
    psc.set_symbol("new", "switch")
end
if psc.eq(cmd1, "bookmark") then
    local marks = {}
    add_bookmark(marks)
    if #marks > 0 then
        psc.set_symbol("set", "switch")
        psc.set_symbol("delete", "switch")
        psc.set_symbol("forget", "switch")
        psc.set_symbol("move", "switch")
        psc.set_symbol("rename", "switch")
        psc.set_symbol("track", "switch")
    end
elseif psc.eq(cmd1, "git") and psc.eq(cmd2, "remote") then
    local remotes = {}
    add_remote(remotes)
    if #remotes > 0 then
        psc.set_symbol("remove", "switch")
        psc.set_symbol("rename", "switch")
        psc.set_symbol("set-url", "switch")
    end
elseif psc.contains({ "git", "rebase" }, cmd1) then
    local marks = {}
    add_bookmark(marks)
    if #marks > 0 then
        psc.set_symbol("--branch", "switch")
        psc.set_symbol("--bookmark", "switch")
    end
end
for _, o in ipairs({ "--from", "--into", "--to", "--revisions", "-r", "--range", "--change", "--onto", "--destination", "--insert-after", "--insert-before", "--revision" }) do
    psc.set_symbol(o, "switch")
end

if psc.eq(cmd1, "new") then
    add_common_revsets(cs)
    add_revsets(cs)
    add_bookmark(cs)
elseif psc.eq(cmd1, "bookmark") and not psc.has_unknown()
    and psc.contains({ "set", "rename", "move", "forget", "delete", "track" }, cmd2) then
    add_bookmark(cs)
elseif psc.eq(cmd1, "git") and not psc.has_unknown() and psc.eq(cmd2, "remote")
    and psc.contains({ "remove", "rename", "set-url" }, cmd3) then
    add_remote(cs)
end

local arg_list = {
    "--revisions", "--revision", "-r",
    "--range", "--onto", "--destination",
    "--insert-after", "--insert-before",
    "--from", "--to", "--into", "--change"
}
local lo = psc.opts[#psc.opts]
for _, o in ipairs(arg_list) do
    if psc.eq(lo, o) then
        add_common_revsets(cs)
        add_revsets(cs)
        break
    end
end
if psc.contains({ "--branch", "--bookmark" }, lo) then
    add_bookmark(cs)
end

return psc.merge(cs)
