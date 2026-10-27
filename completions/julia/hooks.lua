local function default_depot(home)
    if home == "" then
        return nil
    end
    return psc.path(home, ".julia")
end

-- Named environments are directories under <depot>/environments, addressed as @<name>.
local function add_project_envs()
    local home = psc.env("HOME") or psc.env("USERPROFILE") or ""
    local depots = {}
    local configured = psc.env("JULIA_DEPOT_PATH")
    if configured and configured ~= "" then
        local sep = psc.platform == "windows" and ";" or ":"
        for _, depot in ipairs(psc.split(configured, sep)) do
            if depot == "" then
                local fallback = default_depot(home)
                if fallback then
                    depots[#depots + 1] = fallback
                end
            elseif depot:sub(1, 2) == "~/" or depot:sub(1, 2) == "~\\" then
                depots[#depots + 1] = psc.path(home, depot:sub(3))
            else
                depots[#depots + 1] = depot
            end
        end
    else
        local fallback = default_depot(home)
        if fallback then
            depots[1] = fallback
        end
    end
    for _, depot in ipairs(depots) do
        for _, entry in ipairs(psc.ls(psc.path(depot, "environments")) or {}) do
            if entry.is_dir then
                psc.add({
                    name = "@" .. entry.name,
                    tip = {
                        ["en-US"] = "Named environment",
                        ["zh-CN"] = "命名环境",
                    },
                })
            end
        end
    end
end

-- `-C help` is the only enumeration of this build's CPU targets, and it prints to stderr.
local function add_cpu_targets()
    for _, line in ipairs(psc.run({ "julia", "-C", "help" }, { capture_fd = 2 }) or {}) do
        if line:match("^Available features") then
            break
        end
        local name = line:match("^%s*([%-%._%w]+)%s+%-%s+%S")
        if name then
            psc.add({ name = name })
        end
    end
end

psc.on({ option = "--project" }, add_project_envs)

psc.on({ option = "--cpu-target" }, add_cpu_targets)
