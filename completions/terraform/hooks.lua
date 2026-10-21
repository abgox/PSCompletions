local function chdir_args()
    local tokens = psc.tokens or {}
    for i, t in ipairs(tokens) do
        if t.type == "option" and t.name == "-chdir" and tokens[i + 1] then
            return { "-chdir=" .. tokens[i + 1].input }
        end
    end
    return {}
end

local function tf(args, opts)
    local argv = { "terraform" }
    for _, a in ipairs(chdir_args()) do
        argv[#argv + 1] = a
    end
    for _, a in ipairs(args) do
        argv[#argv + 1] = a
    end
    return psc.run(argv, opts)
end

local function add_workspaces()
    local lines = tf({ "workspace", "list" }) or {}
    for _, l in ipairs(lines) do
        local name = l:match("^%*?%s*(%S+)")
        if name and name ~= "" then
            local tip = l:match("%*") and "current workspace" or "workspace"
            psc.add({ name = name, tip = tip })
        end
    end
end

local function add_resources()
    local lines = tf({ "state", "list" }) or {}
    for _, l in ipairs(lines) do
        local addr = psc.trim(l)
        if addr ~= "" then
            psc.add({ name = addr, tip = "resource" })
        end
    end
end

-- `terraform output -json` yields {name: {value: ..., type: ...}}, so the value
-- can go straight into the tip. Single path: -json has been accepted since 0.12,
-- and when the command fails (no init, no state) the plain form fails too, so a
-- retry would only produce items the first call had already ruled out.
local function add_outputs()
    local data = tf({ "output", "-json" }, { format = "json" })
    if not data or type(data) ~= "table" then return end
    for k, v in pairs(data) do
        local tip = ""
        if type(v) == "table" and v.value ~= nil then
            tip = tostring(v.value)
        end
        psc.add({ name = k, tip = tip })
    end
end

psc.on({
    { command = { "workspace", "select" } },
    { command = { "workspace", "delete" } }
}, add_workspaces)

psc.on({
    { command = { "state", "show" } },
    { command = { "state", "rm" }, multiple = true },
    { command = { "state", "mv" }, multiple = true },
    { command = "taint" },
    { command = "untaint" },
    { command = "import" },
    { option = "-target", multiple = true },
    { option = "-replace", multiple = true }
}, add_resources)

psc.on({ command = "output" }, add_outputs)
