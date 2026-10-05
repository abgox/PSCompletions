local function add_workspaces()
    local lines = psc.run({ "terraform", "workspace", "list" }) or {}
    for _, l in ipairs(lines) do
        -- lines like "* default" or "  dev"
        local name = l:match("^%*?%s*(%S+)")
        if name and name ~= "" then
            local tip = l:match("%*") and "current workspace" or "workspace"
            psc.add({ name = name, tip = tip })
        end
    end
end

local function add_resources()
    local lines = psc.run({ "terraform", "state", "list" }) or {}
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
    local data = psc.run({ "terraform", "output", "-json" }, { format = "json" })
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
    { command = { "workspace", "delete" } },
    { command = { "workspace", "show" } },
    { command = "workspace", multiple = true }
}, add_workspaces)

psc.on({
    { command = { "state", "show" }, multiple = true },
    { command = { "state", "rm" }, multiple = true },
    { command = { "state", "mv" }, multiple = true },
    { command = { "state", "pull" } },
    { command = { "state", "push" } },
    { command = "taint", multiple = true },
    { command = "untaint", multiple = true },
    { command = "import", multiple = true },
    { option = "-target" },
    { option = "-replace" }
}, add_resources)

psc.on({
    { command = "output", multiple = true }
}, add_outputs)
