-- `help` takes the tool's own command names.
psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
