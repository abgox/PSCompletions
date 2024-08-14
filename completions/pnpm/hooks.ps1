function handleCompletions($completions) {
    if (!(Test-Path "package.json")) { return $completions }
    $tempList = @()
    function returnCompletion($name, $tip = ' ', $symbol = '') {
        $symbols = foreach ($c in ($symbol -split ' ')) { $PSCompletions.config."symbol_$($c)" }
        $symbols = $symbols -join ''
        $padSymbols = if ($symbols) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbols)" }else { '' }
        $cmd_arr = $name -split ' '

        @{
            name           = $name
            ListItemText   = "$($cmd_arr[-1])$($padSymbols)"
            CompletionText = $cmd_arr[-1]
            ToolTip        = $tip
        }
    }

    $packageJson = $PSCompletions.ConvertFrom_JsonToHashtable((Get-Content "package.json" -Raw))
    $scripts = $packageJson.scripts
    $dependencies = $packageJson.dependencies
    $devDependencies = $packageJson.devDependencies
    if ($scripts) {
        foreach ($script in $scripts.Keys) {
            $tempList += returnCompletion "run $script" "package.json scripts:`n$($scripts.$script)"
        }
    }
    if ($dependencies) {
        foreach ($dependency in $dependencies.Keys) {
            $tempList += returnCompletion "rm $dependency" "Remove dependency: $($dependency) ($($dependencies.$dependency))"
            $tempList += returnCompletion "remove $dependency" "Remove dependency: $($dependency) ($($dependencies.$dependency))"

            $tempList += returnCompletion "update $dependency" "Current Version: $($dependencies.$dependency)"
            $tempList += returnCompletion "up $dependency" "Current Version: $($dependencies.$dependency)"
            $tempList += returnCompletion "upgrade $dependency" "Current Version: $($dependencies.$dependency)"
        }
    }
    if ($devDependencies) {
        foreach ($devDependency in $devDependencies.Keys) {
            $tempList += returnCompletion "rm $devDependency" "Remove devDependency: $($devDependency) ($($devDependencies.$devDependency))"
            $tempList += returnCompletion "remove $devDependency" "Remove devDependency: $($devDependency) ($($devDependencies.$devDependency))"

            $tempList += returnCompletion "update $devDependency" "Current Version: $($devDependencies.$devDependency)"
            $tempList += returnCompletion "up $devDependency" "Current Version: $($devDependencies.$devDependency)"
            $tempList += returnCompletion "upgrade $devDependency" "Current Version: $($devDependencies.$devDependency)"
        }
    }
    return $tempList + $completions
}
