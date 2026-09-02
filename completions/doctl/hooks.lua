-- helper: run doctl list and add each non-empty trimmed line
local function add_from_run(argv, tip_prefix)
    local lines = psc.run(argv)
    if not lines then return end
    for _, line in ipairs(lines) do
        local name = psc.trim(line)
        if name ~= "" and name ~= "Name" and not name:match("^%-") then
            if tip_prefix then
                psc.add({ name = name, tip = tip_prefix .. " --- " .. name })
            else
                psc.add({ name = name })
            end
        end
    end
end

local function add_droplets()
    add_from_run({ "doctl", "compute", "droplet", "list", "--format", "Name", "--no-header" }, "droplet")
end

local function add_droplet_ids()
    local lines = psc.run({ "doctl", "compute", "droplet", "list", "--format", "ID,Name", "--no-header" })
    if not lines then return end
    for _, line in ipairs(lines) do
        local id, name = line:match("^(%S+)%s+(%S+)")
        if id then
            psc.add({ name = id, tip = name or "droplet" })
            if name then psc.add({ name = name, tip = "droplet --- " .. id }) end
        else
            local t = psc.trim(line)
            if t ~= "" then psc.add({ name = t, tip = "droplet" }) end
        end
    end
end

local function add_databases()
    add_from_run({ "doctl", "databases", "list", "--format", "Name", "--no-header" }, "database")
end

local function add_k8s_clusters()
    add_from_run({ "doctl", "kubernetes", "clusters", "list", "--format", "Name", "--no-header" }, "k8s cluster")
end

local function add_domains()
    add_from_run({ "doctl", "compute", "domain", "list", "--format", "Domain", "--no-header" }, "domain")
end

local function add_ssh_keys()
    add_from_run({ "doctl", "compute", "ssh-key", "list", "--format", "Name", "--no-header" }, "ssh-key")
end

local function add_volumes()
    add_from_run({ "doctl", "compute", "volume", "list", "--format", "Name", "--no-header" }, "volume")
end

local function add_load_balancers()
    add_from_run({ "doctl", "compute", "load-balancer", "list", "--format", "Name", "--no-header" }, "load balancer")
end

local function add_certificates()
    add_from_run({ "doctl", "compute", "certificate", "list", "--format", "Name", "--no-header" }, "certificate")
end

local function add_apps()
    add_from_run({ "doctl", "apps", "list", "--format", "ID", "--no-header" }, "app")
end

local function add_tags()
    add_from_run({ "doctl", "compute", "tag", "list", "--format", "Name", "--no-header" }, "tag")
end

local function add_images()
    add_from_run({ "doctl", "compute", "image", "list", "--format", "Name", "--no-header" }, "image")
end

local function add_regions()
    add_from_run({ "doctl", "compute", "region", "list", "--format", "Slug", "--no-header" }, "region")
end

local function add_sizes()
    add_from_run({ "doctl", "compute", "size", "list", "--format", "Slug", "--no-header" }, "size")
end

psc.on({
    { command = { "compute", "droplet", "" } },
    { command = { "compute", "ssh", "" } }
}, add_droplets)

psc.on({
    { command = { "compute", "droplet", "" },   multiple = true },
    { command = { "compute", "droplet-action" } },
    { option = "--droplet-ids" }
}, add_droplet_ids)

psc.on({ command = { "compute", "domain", "" } }, add_domains)

psc.on({
    { command = { "compute", "ssh-key", "" } },
    { option = "--ssh-keys" }
}, add_ssh_keys)

psc.on({ command = { "compute", "volume", "" } }, add_volumes)

psc.on({ command = { "compute", "load-balancer", "" } }, add_load_balancers)

psc.on({ command = { "compute", "certificate", "" } }, add_certificates)

psc.on({
    { command = { "compute", "tag", "" } },
    { option = "--tag-name" }
}, add_tags)

psc.on({
    { command = { "compute", "image", "" } },
    { option = "--image" }
}, add_images)

psc.on({
    { command = { "databases", "" } },
    { command = { "databases", "db", "" } }
}, add_databases)

psc.on({
    { command = { "kubernetes", "clusters", "" } },
    { command = { "kubernetes", "" } }
}, add_k8s_clusters)

psc.on({
    { command = { "apps", "" } },
    { command = { "apps", "spec", "" } }
}, add_apps)

psc.on({ option = "--region" }, add_regions)

psc.on({ option = "--size" }, add_sizes)

psc.on({ option = "--vpc-uuid" }, function()
    local lines = psc.run({ "doctl", "vpcs", "list", "--format", "ID", "--no-header" })
    if not lines then return end
    for _, l in ipairs(lines) do
        local t = psc.trim(l)
        if t ~= "" then psc.add({ name = t, tip = "vpc" }) end
    end
end)
