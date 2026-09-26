local function add_tasks()
    local tasks = psc.run({ "fluxdown", "--json", "list" }, { format = "json", timeout = 3000 }) or {}
    for _, task in ipairs(tasks) do
        if task.taskId and task.taskId ~= "" then
            local label = task.fileName
            if not label or label == "" then
                label = task.url or task.taskId
            end
            psc.add({
                name = task.taskId,
                tip = {
                    ["en-US"] = "Task: " .. label .. " (status " .. tostring(task.status or "?") .. ")",
                    ["zh-CN"] = "任务：" .. label .. "（状态 " .. tostring(task.status or "?") .. "）"
                }
            })
        end
    end
end

local function add_queues()
    local queues = psc.run({ "fluxdown", "--json", "queue" }, { format = "json", timeout = 3000 }) or {}
    for _, queue in ipairs(queues) do
        if queue.queueId and queue.queueId ~= "" then
            local label = queue.name
            if not label or label == "" then
                label = queue.queueId
            end
            local state = queue.isRunning and "running" or "stopped"
            psc.add({
                name = queue.queueId,
                tip = {
                    ["en-US"] = "Queue: " .. label .. " (" .. state .. ")",
                    ["zh-CN"] = "队列：" .. label .. "（" .. state .. "）"
                }
            })
        end
    end
end

local function add_rss_sources()
    local sources = psc.run({ "fluxdown", "--json", "rss", "list" }, { format = "json", timeout = 3000 }) or {}
    for _, source in ipairs(sources) do
        if source.sourceId and source.sourceId ~= "" then
            local label = source.name
            if not label or label == "" then
                label = source.url or source.sourceId
            end
            local unread = tostring(source.unreadCount or 0)
            psc.add({
                name = source.sourceId,
                tip = {
                    ["en-US"] = "RSS: " .. label .. " (" .. unread .. " unread)",
                    ["zh-CN"] = "RSS：" .. label .. "（" .. unread .. " 条未读）"
                }
            })
        end
    end
end

local function add_config_keys()
    psc.add(psc.mount_items({ "next", "config", "set", "next" }))
end

psc.on({
    { command = "status" },
    { command = "pause" },
    { command = "resume" },
    { command = "rm" },
    { command = "watch" }
}, add_tasks)

psc.on({
    { command = "add",            option = "--queue" },
    { command = { "rss", "add" }, option = "--queue" }
}, add_queues)

psc.on({
    { command = { "rss", "rm" } },
    { command = { "rss", "refresh" } },
    { command = { "rss", "items" } }
}, add_rss_sources)

psc.on({
    { command = { "config", "get" } },
    { command = { "config", "unset" } }
}, add_config_keys)
