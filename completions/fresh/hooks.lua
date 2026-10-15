-- --cmd takes the rest of the line, so the daemon-name slot is located by
-- reading the values already typed after it
local function at_cmd_name_slot()
    local chain = {}
    local seen_cmd = false
    for _, token in ipairs(psc.tokens) do
        if not seen_cmd then
            if token.type == "option" and psc.eq(token.name, "--cmd") then
                seen_cmd = true
            end
        elseif token.type ~= "value" then
            return false
        else
            chain[#chain + 1] = token.input
        end
    end
    if not seen_cmd or #chain ~= 2 then
        return false
    end
    if not psc.eq(chain[1], "daemon") and not psc.eq(chain[1], "session") then
        return false
    end
    return psc.eq(chain[2], "attach") or psc.eq(chain[2], "kill")
        or psc.eq(chain[2], "open-file")
end

local function add_daemon_names()
    local last = psc.tokens[#psc.tokens]
    if last and last.type == "option" and psc.eq(last.name, "--attach") then
        -- value slot of -a/--attach, offer directly
    elseif not at_cmd_name_slot() then
        return
    end
    local names = {}
    for _, line in ipairs(psc.run({ "fresh", "--cmd", "daemon", "list" }) or {}) do
        local text = psc.trim(line)
        if text ~= "" and text ~= "No running daemons." and text ~= "Running daemons:"
            and not text:match("^Attach with") and not text:match("^Cleaned up") then
            names[#names + 1] = text
        end
    end
    psc.add(psc.items(names))
end

psc.on({
    { option = "--attach" },
    { option = "--cmd", multiple = true },
}, add_daemon_names)
