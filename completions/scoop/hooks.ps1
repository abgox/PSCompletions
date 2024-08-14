function handleCompletions($completions) {
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

    if ($PSVersionTable.Platform -ne 'Unix') {
        try {
            $config = $PSCompletions.get_raw_content("$env:UserProfile\.config\scoop\config.json") | ConvertFrom-Json
            if ($env:SCOOP) {
                $scoop_path = $env:SCOOP
            }
            else {
                $path = $config.root_path
                if ($path) { [environment]::SetEnvironmentvariable('SCOOP', $path, 'User') }
                $scoop_path = $path
            }

            if ($env:SCOOP_GLOBAL) {
                $scoop_global_path = $env:SCOOP_GLOBAL
            }
            else {
                $path = $config.global_path
                if ($path) { [environment]::SetEnvironmentvariable('SCOOP_GLOBAL', $path, 'User') }
                $scoop_global_path = $path
            }
            foreach ($_ in scoop bucket known) {
                $bucket = $_
                $completions += returnCompletion "bucket add $($bucket)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.bucket.add)
            }
            foreach ($_ in Get-ChildItem "$scoop_path\buckets" 2>$null) {
                $bucket = $_.Name
                $completions += returnCompletion "bucket rm $($bucket)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.bucket.rm)
            }
            foreach ($_ in @("$scoop_path\apps", "$scoop_global_path\apps")) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    $completions += returnCompletion "uninstall $($app)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.uninstall)
                    $completions += returnCompletion "update $($app)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.update)
                    $completions += returnCompletion "cleanup $($app)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.cleanup)
                    $completions += returnCompletion "hold $($app)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.hold)
                    $completions += returnCompletion "unhold $($app)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.unhold)
                    $completions += returnCompletion "prefix $($app)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.prefix)
                }
            }
            foreach ($_ in Get-ChildItem "$scoop_path\cache" -ErrorAction SilentlyContinue) {
                $match = $_.BaseName -match '^([^#]+#[^#]+)'
                if ($match) {
                    $part = $_.Name -split "#"
                    $path = $_.FullName
                    $cache = $part[0..1] -join "#"
                    $completions += returnCompletion "cache rm $($cache)" $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.cache.rm)
                }
            }
        }
        catch {}
    }
    return $completions
}
