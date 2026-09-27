psc.on({ option = "--project" }, function()
    for _, p in ipairs(psc.glob("tsconfig*.json") or {}) do psc.add({ name = p }) end
end)
