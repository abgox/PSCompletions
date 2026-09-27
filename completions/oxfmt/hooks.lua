psc.on({ option = "--config" }, function()
    for _, p in ipairs(psc.glob("{.oxfmtrc,oxfmt}.json") or {}) do psc.add({ name = p }) end
end)
