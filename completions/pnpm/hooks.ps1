function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    if (!(Test-Path "package.json")) { return $completions }

    function addCompletion($name, $tip = ' ', $symbol = '') {
        $symbols = foreach ($c in ($symbol -split ' ')) { $PSCompletions.config."symbol_$($c)" }
        $symbols = $symbols -join ''
        $padSymbols = if ($symbols) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbols)" }else { '' }
        $cmd_arr = $name -split ' '

        $completions.Add(@{
                name           = $name
                ListItemText   = "$($cmd_arr[-1])$($padSymbols)"
                CompletionText = $cmd_arr[-1]
                ToolTip        = $tip
            })
    }

    $packageJson = $PSCompletions.ConvertFrom_JsonToHashtable((Get-Content "package.json" -Raw))
    $scripts = $packageJson.scripts
    $dependencies = $packageJson.dependencies
    $devDependencies = $packageJson.devDependencies
    if ($scripts) {
        foreach ($script in $scripts.Keys) {
            addCompletion "run $script" "package.json scripts:`n$($scripts.$script)"
        }
    }
    if ($dependencies) {
        foreach ($dependency in $dependencies.Keys) {
            addCompletion "rm $dependency" "Remove dependency: $($dependency) ($($dependencies.$dependency))"
            addCompletion "remove $dependency" "Remove dependency: $($dependency) ($($dependencies.$dependency))"

            addCompletion "update $dependency" "Current Version: $($dependencies.$dependency)"
            addCompletion "up $dependency" "Current Version: $($dependencies.$dependency)"
            addCompletion "upgrade $dependency" "Current Version: $($dependencies.$dependency)"
        }
    }
    if ($devDependencies) {
        foreach ($devDependency in $devDependencies.Keys) {
            addCompletion "rm $devDependency" "Remove devDependency: $($devDependency) ($($devDependencies.$devDependency))"
            addCompletion "remove $devDependency" "Remove devDependency: $($devDependency) ($($devDependencies.$devDependency))"

            addCompletion "update $devDependency" "Current Version: $($devDependencies.$devDependency)"
            addCompletion "up $devDependency" "Current Version: $($devDependencies.$devDependency)"
            addCompletion "upgrade $devDependency" "Current Version: $($devDependencies.$devDependency)"
        }
    }
    return $completions
}
