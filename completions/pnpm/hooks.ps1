function handleCompletions($completions) {
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
            $tempList += $PSCompletions.return_completion("rm $dependency", "Remove dependency: $($dependency) ($($dependencies.$dependency))")
            $tempList += $PSCompletions.return_completion("remove $dependency", "Remove dependency: $($dependency) ($($dependencies.$dependency))")

            $tempList += $PSCompletions.return_completion("update $dependency", "Current Version: $($dependencies.$dependency)")
            $tempList += $PSCompletions.return_completion("up $dependency", "Current Version: $($dependencies.$dependency)")
            $tempList += $PSCompletions.return_completion("upgrade $dependency", "Current Version: $($dependencies.$dependency)")
        }
    }
    if ($devDependencies) {
        foreach ($devDependency in $devDependencies.Keys) {
            $tempList += $PSCompletions.return_completion("rm $devDependency", "Remove devDependency: $($devDependency) ($($devDependencies.$devDependency))")
            $tempList += $PSCompletions.return_completion("remove $devDependency", "Remove devDependency: $($devDependency) ($($devDependencies.$devDependency))")

            $tempList += $PSCompletions.return_completion("update $devDependency", "Current Version: $($devDependencies.$devDependency)")
            $tempList += $PSCompletions.return_completion("up $devDependency", "Current Version: $($devDependencies.$devDependency)")
            $tempList += $PSCompletions.return_completion("upgrade $devDependency", "Current Version: $($devDependencies.$devDependency)")
        }
    }
    return $tempList + $completions
}
