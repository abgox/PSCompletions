local function add_dotfiles()
    for _, p in ipairs(psc.glob("{.env,.secrets,.vars,.input}") or {}) do psc.add({ name = p }) end
end

psc.on({
    { option = "--env-file" },
    { option = "--secret-file" },
    { option = "--var-file" },
    { option = "--input-file" },
}, add_dotfiles)
