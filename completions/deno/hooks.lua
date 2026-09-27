local function add_tasks()
    -- tasks and imports from deno config
    local batch = psc.json_batch({ "deno.json", "deno.jsonc" })
    for _, cfg in pairs(batch) do
        if cfg then
            if cfg.tasks then
                for k, v in pairs(cfg.tasks) do
                    -- tasks may be string or object; normalize with psc.join
                    psc.add({ name = k, tip = psc.join(v, "\n") })
                end
            end
            if cfg.imports then
                for k, v in pairs(cfg.imports) do
                    psc.add({ name = k, tip = psc.join(v, "\n") })
                end
            end
        end
    end
end

psc.on({ command = "task" }, add_tasks)

psc.on({ option = "--config" }, function()
    for _, p in ipairs(psc.glob("{deno.json,deno.jsonc}") or {}) do psc.add({ name = p }) end
end)
