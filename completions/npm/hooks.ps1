function handleCompletions($completions) {
    if ($completions -isnot [array]) {
        return $completions
    }
    if (!(Test-Path "package.json")) { return $completions }
    $tempList = @()

    $packageJson = $PSCompletions.ConvertFrom_JsonToHashtable((Get-Content "package.json" -Raw -Encoding utf8))
    $scripts = $packageJson.scripts
    $dependencies = $packageJson.dependencies
    $devDependencies = $packageJson.devDependencies
    if ($scripts) {
        foreach ($script in $scripts.Keys) {
            $tempList += $PSCompletions.return_completion("run $script", "package.json scripts:`n$($scripts.$script)")
        }
    }
    if ($dependencies) {
        foreach ($dependency in $dependencies.Keys) {
            $tempList += $PSCompletions.return_completion("uninstall $dependency", "Uninstall dependency: $($dependency) ($($dependencies.$dependency))")
            $tempList += $PSCompletions.return_completion("update $dependency", "Current Version: $($dependencies.$dependency)")
        }
    }
    if ($devDependencies) {
        foreach ($devDependency in $devDependencies.Keys) {
            $tempList += $PSCompletions.return_completion("uninstall $devDependency", "Uninstall devDependency: $($devDependency) ($($devDependencies.$devDependency))")
            $tempList += $PSCompletions.return_completion("update $devDependency", "Current Version: $($devDependencies.$devDependency)")
        }
    }
    return $tempList + $completions
}
