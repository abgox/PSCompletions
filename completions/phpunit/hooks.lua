-- phpunit may be a .bat shim on Windows, so these queries go through the shell.
local function add_suites()
    for _, line in ipairs(psc.run({ "phpunit", "--list-suites" }, { shell = true }) or {}) do
        local name, count = line:match("^ %- (.+) %((%d+) tests?%)$")
        if name then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = count .. (count == "1" and " test" or " tests"),
                    ["zh-CN"] = count .. " 个测试",
                },
            })
        end
    end
end

local function add_groups()
    for _, line in ipairs(psc.run({ "phpunit", "--list-groups" }, { shell = true }) or {}) do
        local name, count = line:match("^ %- (.+) %((%d+) tests?%)$")
        if name then
            psc.add({
                name = name,
                tip = {
                    ["en-US"] = count .. (count == "1" and " test" or " tests"),
                    ["zh-CN"] = count .. " 个测试",
                },
            })
        end
    end
end

local function add_test_ids()
    for _, line in ipairs(psc.run({ "phpunit", "--list-test-ids" }, { shell = true }) or {}) do
        if line:match("^%S+::%S") then
            psc.add({ name = line })
        end
    end
end

-- phpunit cannot list PHP extensions, so the runtime registry is the source.
local function add_php_extensions()
    for _, name in ipairs(psc.run({ "php", "-r", "echo implode(PHP_EOL, get_loaded_extensions()), PHP_EOL;" }) or {}) do
        psc.add({ name = name })
    end
end

psc.on({
    { option = "--testsuite" },
    { option = "--exclude-testsuite" },
}, add_suites)

psc.on({
    { option = "--group" },
    { option = "--exclude-group" },
}, add_groups)

psc.on({ option = "--run-test-id" }, add_test_ids)

psc.on({ option = "--requires-php-extension" }, add_php_extensions)
