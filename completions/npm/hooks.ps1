function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    if (!(Test-Path "package.json")) { return $completions }

    $tempList = [System.Collections.Generic.List[System.Object]]@()
    function addCompletion($name, $tip = ' ', $symbol = '') {
        $symbols = foreach ($c in ($symbol -split ' ')) { $PSCompletions.config."symbol_$($c)" }
        $symbols = $symbols -join ''
        $padSymbols = if ($symbols) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbols)" }else { '' }
        $cmd_arr = $name -split ' '

        $tempList.Add(@{
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
            addCompletion "uninstall $dependency" "Uninstall dependency: $($dependency) ($($dependencies.$dependency))"

            addCompletion "update $dependency" "Current Version: $($dependencies.$dependency)"
        }
    }
    if ($devDependencies) {
        foreach ($devDependency in $devDependencies.Keys) {
            addCompletion "uninstall $devDependency" "Uninstall devDependency: $($devDependency) ($($devDependencies.$devDependency))"

            addCompletion "update $devDependency" "Current Version: $($devDependencies.$devDependency)"
        }
    }
    return $tempList + $completions
}
