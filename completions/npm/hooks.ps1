function handleCompletions($completions) {
    if (!(Test-Path 'package.json')) { return $completions }
    $tempList = @()

    $packageJson = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content('package.json'))
    $scripts = $packageJson.scripts
    $dependencies = $packageJson.dependencies
    $devDependencies = $packageJson.devDependencies

    $filter_input_arr = $PSCompletions.filter_input_arr

    switch ($filter_input_arr[-1]) {
        'run' {
            if ($scripts) {
                foreach ($script in $scripts.Keys) {
                    $tempList += $PSCompletions.return_completion($script, "package.json scripts:`n$($scripts.$script)")
                }
            }
        }
        'uninstall' {
            if ($dependencies) {
                foreach ($dependency in $dependencies.Keys) {
                    $tempList += $PSCompletions.return_completion($dependency, "Uninstall dependency: $($dependency) ($($dependencies.$dependency))")
                }
            }
            if ($devDependencies) {
                foreach ($devDependency in $devDependencies.Keys) {
                    $tempList += $PSCompletions.return_completion($devDependency, "Uninstall devDependency: $($devDependency) ($($devDependencies.$devDependency))")
                }
            }
        }
        'update' {
            if ($dependencies) {
                foreach ($dependency in $dependencies.Keys) {
                    $tempList += $PSCompletions.return_completion($dependency, "Current Version: $($dependencies.$dependency)")
                }
            }
            if ($devDependencies) {
                foreach ($devDependency in $devDependencies.Keys) {
                    $tempList += $PSCompletions.return_completion($devDependency, "Current Version: $($devDependencies.$devDependency)")
                }
            }
        }
    }
    return $tempList + $completions
}
