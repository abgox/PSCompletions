function handleCompletions($completions) {

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
                $completions += $PSCompletions.return_completion("bucket add $($bucket)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.bucket.add))
            }
            foreach ($_ in Get-ChildItem "$scoop_path\buckets" 2>$null) {
                $bucket = $_.Name
                $completions += $PSCompletions.return_completion("bucket rm $($bucket)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.bucket.rm))
            }
            foreach ($_ in @("$scoop_path\apps", "$scoop_global_path\apps")) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    $completions += $PSCompletions.return_completion("uninstall $($app)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.uninstall))
                    $completions += $PSCompletions.return_completion("update $($app)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.update))
                    $completions += $PSCompletions.return_completion("cleanup $($app)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cleanup))
                    $completions += $PSCompletions.return_completion("hold $($app)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.hold))
                    $completions += $PSCompletions.return_completion("unhold $($app)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.unhold))
                    $completions += $PSCompletions.return_completion("prefix $($app)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.prefix))
                }
            }
            foreach ($_ in Get-ChildItem "$scoop_path\cache" -ErrorAction SilentlyContinue) {
                $match = $_.BaseName -match '^([^#]+#[^#]+)'
                if ($match) {
                    $part = $_.Name -split "#"
                    $path = $_.FullName
                    $cache = $part[0..1] -join "#"
                    $completions += $PSCompletions.return_completion("cache rm $($cache)", $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cache.rm))
                }
            }
        }
        catch {}
    }
    return $completions
}
