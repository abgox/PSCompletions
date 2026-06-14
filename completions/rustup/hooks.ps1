# Refer to: https://pscompletions.abgox.com/docs/completion/hooks
function handleCompletions($completions) {
    $list = @()

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude option parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    function return_toolchains {
        return rustup toolchain list -q 2>$null
    }

    function return_targets {
        return rustup target list --installed -q 2>$null
    }

    function return_targets_all {
        return rustup target list -q 2>$null
    }

    function return_components {
        return rustup component list --installed -q 2>$null
    }

    function return_components_all {
        return rustup component list -q 2>$null
    }

    switch ($last_item) {
        'default' {
            $toolchains = return_toolchains
            foreach ($_ in $toolchains) {
                $list += $PSCompletions.return_completion($_, "toolchain --- $_")
            }
            $list += $PSCompletions.return_completion('none', 'Remove the default toolchain')
        }
        'uninstall' {
            $toolchains = return_toolchains
            foreach ($_ in $toolchains) {
                $list += $PSCompletions.return_completion($_, "toolchain --- $_")
            }
        }
        'set' {
            if ($first_item -eq 'override') {
                $toolchains = return_toolchains
                foreach ($_ in $toolchains) {
                    $list += $PSCompletions.return_completion($_, "toolchain --- $_")
                }
            }
        }
        'run' {
            $toolchains = return_toolchains
            foreach ($_ in $toolchains) {
                $list += $PSCompletions.return_completion($_, "toolchain --- $_")
            }
        }
    }

    # For toolchain uninstall subcommand
    if ($first_item -eq 'toolchain' -and $last_item -eq 'uninstall') {
        $toolchains = return_toolchains
        foreach ($_ in $toolchains) {
            $list += $PSCompletions.return_completion($_, "toolchain --- $_")
        }
    }

    # For target remove subcommand
    if ($first_item -eq 'target' -and $last_item -eq 'remove') {
        $targets = return_targets
        foreach ($_ in $targets) {
            $list += $PSCompletions.return_completion($_, "target --- $_")
        }
    }

    # For component remove subcommand
    if ($first_item -eq 'component' -and $last_item -eq 'remove') {
        $components = return_components
        foreach ($_ in $components) {
            $list += $PSCompletions.return_completion($_, "component --- $_")
        }
    }

    # For toolchain install subcommand
    if ($first_item -eq 'toolchain' -and $last_item -eq 'install') {
        $toolchains = return_toolchains
        foreach ($_ in $toolchains) {
            $list += $PSCompletions.return_completion($_, "toolchain --- $_")
        }
    }

    # For target add subcommand
    if ($first_item -eq 'target' -and $last_item -eq 'add') {
        $targets = return_targets_all
        foreach ($_ in $targets) {
            $list += $PSCompletions.return_completion($_, "target --- $_")
        }
    }

    # For component add subcommand
    if ($first_item -eq 'component' -and $last_item -eq 'add') {
        $components = return_components_all
        foreach ($_ in $components) {
            $list += $PSCompletions.return_completion($_, "component --- $_")
        }
    }

    return $list + $completions
}
