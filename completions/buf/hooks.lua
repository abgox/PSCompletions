local function add_protos()
    psc.add(psc.items(psc.glob("**/*.proto") or {}, function(p) return { name = p } end))
end

local function add_buf_yaml()
    psc.add(psc.items(psc.concat(psc.glob("buf.yaml") or {}, psc.glob("buf.work.yaml") or {}),
        function(p) return { name = p } end))
end

local function add_gen_yaml()
    psc.add(psc.items(psc.glob("buf.gen.yaml") or {}, function(p) return { name = p } end))
end

local function add_wasm()
    psc.add(psc.items(psc.glob("**/*.wasm") or {}, function(p) return { name = p } end))
end

local function add_netrc()
    psc.add(psc.items(psc.glob("{.netrc,_netrc}") or {}, function(p) return { name = p } end))
end

psc.on({
    { command = "breaking" },
    { command = "build" },
    { command = "convert" },
    { command = "export" },
    { command = "format" },
    { command = "generate" },
    { command = "lint" },
    { command = "ls-files" },
    { command = "stats" },
    { command = { "beta", "price" } },
    { command = { "dep", "graph" } },
    { command = { "source", "edit", "deprecate" } },
    { option = "--against" },
    { option = "--schema", multiple = true },
}, add_protos)

psc.on({
    { option = "--config" },
    { option = "--against-config" },
}, add_buf_yaml)

psc.on({
    { option = "--template" },
    { option = "--buf-gen-yaml" },
}, add_gen_yaml)

psc.on({ option = "--binary" }, add_wasm)

psc.on({ option = "--netrc-file" }, add_netrc)

psc.on({
    { option = "--path", multiple = true },
    { option = "--exclude-path", multiple = true },
}, add_protos)
