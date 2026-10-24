local function add_targets()
    local text = psc.read("GNUmakefile") or psc.read("makefile") or psc.read("Makefile")
    if not text then
        return
    end
    local seen = {}
    local function add(name)
        if name == ".PHONY" or name:match("^%.") or name:match("[%%%$]") or name:match("/") then
            return
        end
        if not seen[name] then
            seen[name] = true
            psc.add({ name = name, tip = { ["en-US"] = "target", ["zh-CN"] = "目标" } })
        end
    end
    for line in text:gmatch("[^\r\n]+") do
        local clean = line:gsub("#.*$", "")
        if clean:match("%S") and not clean:match("^\t") and not clean:match(":%s*=") then
            local target, prerequisite = clean:match("^([^:]+):(.*)$")
            if target and not target:match("=") then
                if target:match("%.PHONY") then
                    for name in prerequisite:gmatch("%S+") do
                        add(name)
                    end
                else
                    for name in target:gmatch("%S+") do
                        add(name)
                    end
                end
            end
        end
    end
end

psc.on({ multiple = true }, add_targets)
