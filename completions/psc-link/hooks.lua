local function add_completions()
    for _, entry in ipairs(psc.ls("completions") or {}) do
        if entry.is_dir then
            psc.add({
                name = entry.name,
                tip = function()
                    local manifest = psc.json(psc.path(entry.path, "language", psc.config.language .. ".json"))
                    if not manifest then
                        return
                    end
                    local meta = manifest.meta
                    local lines = {}
                    if meta.url then
                        table.insert(lines, "url: " .. meta.url)
                    end
                    if meta.description then
                        table.insert(lines, "-----")
                        table.insert(lines, psc.join(meta.description, "\n"))
                    end
                    return psc.join(lines, "\n")
                end
            })
        end
    end
end

psc.on({ multiple = true }, add_completions)
