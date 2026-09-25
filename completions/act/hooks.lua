local function add_env_file()
    psc.add(psc.items(psc.glob(".env") or {}))
end

local function add_secret_file()
    psc.add(psc.items(psc.glob(".secrets") or {}))
end

local function add_var_file()
    psc.add(psc.items(psc.glob(".vars") or {}))
end

local function add_input_file()
    psc.add(psc.items(psc.glob(".input") or {}))
end

psc.on({ option = "--env-file" }, add_env_file)

psc.on({ option = "--secret-file" }, add_secret_file)

psc.on({ option = "--var-file" }, add_var_file)

psc.on({ option = "--input-file" }, add_input_file)
