-- svn status --xml is the one query every producer needs: entry path, entry status
-- and changelist names, each already filtered by the CLI itself.
local function load_status_text()
    return table.concat(psc.run({ "svn", "status", "--xml" }) or {}, "\n")
end

local STATUS_ZH = {
    modified = "已修改", added = "已添加", deleted = "已删除",
    unversioned = "未纳入版本控制", conflicted = "有冲突", missing = "丢失",
    replaced = "已替换", merged = "已合并", obstructed = "被阻碍",
    external = "外部条目", ignored = "已忽略", incomplete = "不完整",
    normal = "无更改",
}

local function add_changed_files()
    local entries = {}
    for path, item in load_status_text():gmatch('<entry.-path="([^"]*)".-item="([^"]*)"') do
        entries[#entries + 1] = { path = path, item = item }
    end
    psc.add(psc.items(entries, function(e)
        local label = STATUS_ZH[e.item] or e.item
        return {
            name = e.path,
            tip = {
                ["en-US"] = e.item .. " --- " .. e.path,
                ["zh-CN"] = label .. " --- " .. e.path,
            },
        }
    end))
end

local function add_unversioned_files()
    for path, item in load_status_text():gmatch('<entry.-path="([^"]*)".-item="([^"]*)"') do
        if item == "unversioned" then
            psc.add({
                name = path,
                tip = {
                    ["en-US"] = "unversioned --- " .. path,
                    ["zh-CN"] = "未纳入版本控制 --- " .. path,
                },
            })
        end
    end
end

local function add_changelists()
    for name in load_status_text():gmatch('<changelist%s+name="([^"]*)"') do
        psc.add({
            name = name,
            tip = {
                ["en-US"] = "changelist --- " .. name,
                ["zh-CN"] = "更改列表 --- " .. name,
            },
        })
    end
end

-- the `changelist` command's first positional is a changelist name, not a path, so it
-- is left out of the path list below and served by add_changelists instead.
psc.on({
    { command = "annotate",  multiple = true },
    { command = "cat",        multiple = true },
    { command = "cleanup",    multiple = true },
    { command = "commit",     multiple = true },
    { command = "delete",     multiple = true },
    { command = "diff",       multiple = true },
    { command = "info",       multiple = true },
    { command = "lock",       multiple = true },
    { command = "log",        multiple = true },
    { command = "patch",      multiple = true },
    { command = "propdel",    multiple = true },
    { command = "propedit",   multiple = true },
    { command = "propget",    multiple = true },
    { command = "proplist",   multiple = true },
    { command = "propset",    multiple = true },
    { command = "resolve",    multiple = true },
    { command = "resolved",   multiple = true },
    { command = "revert",     multiple = true },
    { command = "status",     multiple = true },
    { command = "unlock",     multiple = true }
}, add_changed_files)

psc.on({ command = "add" }, add_unversioned_files)

psc.on({
    { command = "changelist", multiple = true },
    { option = "--changelist" }
}, add_changelists)
