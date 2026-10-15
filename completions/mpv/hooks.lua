local function lines_after(argv, skip)
    local out = {}
    local lines = psc.run(argv) or {}
    for i = skip + 1, #lines do
        out[#out + 1] = lines[i]
    end
    return out
end

local function add_rows(argv, skip, parse, tip_zh)
    local seen = {}
    for _, line in ipairs(lines_after(argv, skip)) do
        local name, desc = parse(line)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = desc ~= "" and desc or tip_zh,
                    ["zh-CN"] = tip_zh,
                },
            })
        end
    end
end

local function aligned(line)
    local name, desc = line:match("^%s*(%S+)%s%s+(.*)$")
    if name then
        return name, desc
    end
    return (line:match("^%s*(%S+)")), ""
end

local function dashed(line)
    return line:match("^%s*(%S+)%s+-%s+(.*)$")
end

local function quoted(line)
    return line:match("^%s*'(.-)'%s+%((.*)%)%s*$")
end

local function parenthesized(line)
    return line:match("^%s*(%S+)%s+%((.*)%)%s*$")
end

local function add_vo()
    add_rows({ "mpv", "--vo=help" }, 1, aligned, "视频输出")
end

local function add_ao()
    add_rows({ "mpv", "--ao=help" }, 1, aligned, "音频输出")
end

local function add_gpu_contexts()
    add_rows({ "mpv", "--gpu-context=help" }, 1, aligned, "GPU context")
end

local function add_hwdec()
    add_rows({ "mpv", "--hwdec=help" }, 1, parenthesized, "硬解")
end

local function add_ad()
    add_rows({ "mpv", "--ad=help" }, 1, dashed, "音频解码器")
end

local function add_vd()
    add_rows({ "mpv", "--vd=help" }, 1, dashed, "视频解码器")
end

local function add_audio_demuxers()
    add_rows({ "mpv", "--audio-demuxer=help" }, 2, aligned, "demuxer")
end

local function add_sub_demuxers()
    add_rows({ "mpv", "--sub-demuxer=help" }, 2, aligned, "demuxer")
end

local function add_audio_devices()
    add_rows({ "mpv", "--audio-device=help" }, 1, quoted, "音频设备")
end

psc.on({ option = "--vo" }, add_vo)

psc.on({ option = "--ao" }, add_ao)

psc.on({ option = "--gpu-context" }, add_gpu_contexts)

psc.on({ option = "--hwdec" }, add_hwdec)

psc.on({ option = "--ad" }, add_ad)

psc.on({ option = "--vd" }, add_vd)

psc.on({ option = "--audio-demuxer" }, add_audio_demuxers)

psc.on({ option = "--sub-demuxer" }, add_sub_demuxers)

psc.on({ option = "--audio-device" }, add_audio_devices)
