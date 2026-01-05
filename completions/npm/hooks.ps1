function handleCompletions($completions) {
    if (!(Test-Path 'package.json')) { return $completions }
    $list = @()

    $packageJson = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content('package.json'))
    $scripts = $packageJson.scripts
    $dependencies = $packageJson.dependencies
    $devDependencies = $packageJson.devDependencies

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude options parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    switch ($last_item) {
        'run' {
            if ($scripts) {
                foreach ($script in $scripts.Keys) {
                    $list += $PSCompletions.return_completion($script, "package.json scripts:`n$($scripts.$script)")
                }
            }
        }
        'uninstall' {
            if ($dependencies) {
                foreach ($dependency in $dependencies.Keys) {
                    $list += $PSCompletions.return_completion($dependency, "Uninstall dependency: $($dependency) ($($dependencies.$dependency))")
                }
            }
            if ($devDependencies) {
                foreach ($devDependency in $devDependencies.Keys) {
                    $list += $PSCompletions.return_completion($devDependency, "Uninstall devDependency: $($devDependency) ($($devDependencies.$devDependency))")
                }
            }
        }
        'update' {
            if ($dependencies) {
                foreach ($dependency in $dependencies.Keys) {
                    $list += $PSCompletions.return_completion($dependency, "Current Version: $($dependencies.$dependency)")
                }
            }
            if ($devDependencies) {
                foreach ($devDependency in $devDependencies.Keys) {
                    $list += $PSCompletions.return_completion($devDependency, "Current Version: $($devDependencies.$devDependency)")
                }
            }
        }
    }
    return $list + $completions
}
