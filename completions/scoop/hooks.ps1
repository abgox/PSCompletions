function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    function addCompletion($name, $symbol = '', $tip = ' ') {
        $completions.Add(@{
                name   = $name
                symbol = $symbol
                tip    = $tip
            })
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
            scoop bucket known | ForEach-Object {
                $bucket = $_
                addCompletion "bucket add $($bucket)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.bucket.add)
            }
            Get-ChildItem "$scoop_path\buckets" 2>$null | ForEach-Object {
                $bucket = $_.Name
                addCompletion "bucket rm $($bucket)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.bucket.rm)
            }
            @("$scoop_path\apps", "$scoop_global_path\apps") | ForEach-Object {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    addCompletion "uninstall $($app)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.uninstall)
                    addCompletion "update $($app)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.update)
                    addCompletion "cleanup $($app)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.cleanup)
                    addCompletion "hold $($app)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.hold)
                    addCompletion "unhold $($app)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.unhold)
                    addCompletion "prefix $($app)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.prefix)
                }
            }
            Get-ChildItem "$scoop_path\cache" | ForEach-Object {
                $match = $_.BaseName -match '^([^#]+#[^#]+)'
                if ($match) {
                    $part = $_.Name -split "#"
                    $path = $_.FullName
                    $cache = $part[0..1] -join "#"
                    addCompletion "cache rm $($cache)" '' $PSCompletions.replace_content($PSCompletions.data.scoop.info.tip.cache.rm)
                }
            }
        }
        catch {}
    }
    return $completions
}