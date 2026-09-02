local function add_extractors()
    for _, line in ipairs(psc.run({ "yt-dlp", "--list-extractors" }) or {}) do
        local name = psc.trim(line)
        if name ~= "" then psc.add({ name = name, tip = "extractor" }) end
    end
end

psc.on({ option = "--extractor-args" }, add_extractors)
