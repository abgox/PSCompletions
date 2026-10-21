local function add_capability(cmd, pattern, skip)
    local seen = {}
    for _, l in ipairs(psc.run({ "ffmpeg", "-hide_banner", cmd }) or {}) do
        local name = l:match(pattern)
        if name and name ~= skip and not seen[name] then
            seen[name] = true
            psc.add({ name = name })
        end
    end
end

local function add_formats()
    add_capability("-formats", "^%s*[DE][%w.]*%s+(%S+)", "=")
end

local function add_encoders()
    add_capability("-encoders", "^%s*[VAS][A-Z.]*%s+([%w_]+)", "=")
end

local function add_pix_fmts()
    add_capability("-pix_fmts", "^[IO][A-Z.]*%s+([%w_]+)", "=")
end

local function add_sample_fmts()
    add_capability("-sample_fmts", "^(%S+)%s+%d", "name")
end

local function add_layouts()
    local seen = {}
    local inside = false
    for _, l in ipairs(psc.run({ "ffmpeg", "-hide_banner", "-layouts" }) or {}) do
        if l:match("^Standard channel layouts:") then
            inside = true
        elseif inside then
            if l:match("^%s*$") then break end
            local name = l:match("^(%S+)%s+%S")
            if name and name ~= "NAME" and not seen[name] then
                seen[name] = true
                psc.add({ name = name })
            end
        end
    end
end

local function add_bsfs()
    local seen = {}
    for _, l in ipairs(psc.run({ "ffmpeg", "-hide_banner", "-bsfs" }) or {}) do
        local name = l:match("^(%S+)$")
        if name and name ~= "Bitstream" and not seen[name] then
            seen[name] = true
            psc.add({ name = name })
        end
    end
end

psc.on({ option = "-f" }, add_formats)

psc.on({
    { option = "-c" },
    { option = "-codec" },
    { option = "-vcodec" },
    { option = "-acodec" },
    { option = "-dcodec" }
}, add_encoders)

psc.on({ option = "-pix_fmt" }, add_pix_fmts)

psc.on({ option = "-sample_fmt" }, add_sample_fmts)

psc.on({
    { option = "-channel_layout" },
    { option = "-ch_layout" }
}, add_layouts)

psc.on({ option = "-bsf" }, add_bsfs)
