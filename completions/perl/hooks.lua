local ENUMERATE_DIRS = [[
for my $d (@INC, @ARGV) {
    my $p = eval { abs_path($d) };
    print "$p\n" if defined $p && -d $p
}]]

local function get_include_dirs()
    local dirs = {}
    local want_value = false
    for _, token in ipairs(psc.tokens) do
        if want_value and token.type == "value" then
            dirs[#dirs + 1] = token.input
        end
        want_value = token.type == "option" and token.name == "-I"
    end
    return dirs
end

local function add_modules()
    -- -I directories typed on this line are not part of the subprocess's @INC
    local argv = { "perl", "-MCwd=abs_path", "-e", ENUMERATE_DIRS, "--" }
    for _, dir in ipairs(get_include_dirs()) do
        argv[#argv + 1] = dir
    end

    local roots = {}
    local seen_root = {}
    for _, dir in ipairs(psc.run(argv) or {}) do
        dir = dir:gsub("\\", "/"):gsub("/+$", "")
        if dir ~= "" and not seen_root[dir] then
            seen_root[dir] = true
            roots[#roots + 1] = dir
        end
    end

    local seen = {}
    local names = {}

    local function collect(dir)
        for _, path in ipairs(psc.glob(psc.path(dir, "**/*.pm")) or {}) do
            path = path:gsub("\\", "/")
            -- the longest @INC root wins: arch directories are nested under the language root
            local best = ""
            for _, root in ipairs(roots) do
                if #root > #best and path:sub(1, #root + 1) == root .. "/" then
                    best = root
                end
            end
            if best ~= "" then
                local name = path:sub(#best + 2):gsub("/", "::"):gsub("%.pm$", "")
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    names[#names + 1] = name
                end
            end
        end
    end

    for _, dir in ipairs(roots) do
        collect(dir)
    end

    table.sort(names)
    for _, name in ipairs(names) do
        psc.add({ name = name })
    end
end

psc.on({
    { option = "-M" },
    { option = "-m" }
}, add_modules)
