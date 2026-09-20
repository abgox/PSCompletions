local function add_var_files()
    for _, p in ipairs(psc.glob("*.tfvars") or {}) do psc.add({ name = p }) end
end

local function add_state_files()
    for _, p in ipairs(psc.glob("*.tfstate") or {}) do psc.add({ name = p }) end
end

psc.on({ option = "-var-file" }, add_var_files)

psc.on({ option = "-state" }, add_state_files)
