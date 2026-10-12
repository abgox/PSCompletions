local function add_completions()
    for _, entry in ipairs(psc.ls("completions") or {}) do
        if entry.is_dir then
            psc.add({ name = entry.name })
        end
    end
end

psc.on({ multiple = true }, add_completions)
