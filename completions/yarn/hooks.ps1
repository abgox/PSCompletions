function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    if (!(Test-Path "package.json")) { return $completions }

    $tempList = [System.Collections.Generic.List[System.Object]]@()
    function addCompletion($name, $tip = ' ', $symbol = '') {
        $tempList.Add(@{
                name   = $name
                symbol = $symbol
                tip    = $tip
            })
    }

    $packageJson = $PSCompletions.ConvertFrom_JsonToHashtable((Get-Content "package.json" -Raw))
    $scripts = $packageJson.scripts
    $dependencies = $packageJson.dependencies
    $devDependencies = $packageJson.devDependencies
    if ($scripts) {
        foreach ($script in $scripts.Keys) {
            addCompletion $script "package.json scripts:`n$($scripts.$script)"
            addCompletion "run $script" "package.json scripts:`n$($scripts.$script)"
        }
    }
    if ($dependencies) {
        foreach ($dependency in $dependencies.Keys) {
            addCompletion "remove $dependency" "Remove dependency: $($dependency) ($($dependencies.$dependency))"

            addCompletion "upgrade $dependency" "Current Version: $($dependencies.$dependency)"
        }
    }
    if ($devDependencies) {
        foreach ($devDependency in $devDependencies.Keys) {
            addCompletion "remove $devDependency" "Remove devDependency: $($devDependency) ($($devDependencies.$devDependency))"

            addCompletion "upgrade $devDependency" "Current Version: $($devDependencies.$devDependency)"
        }
    }
    return $tempList + $completions
}
