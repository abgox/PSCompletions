function handleCompletions($completions) {
    $tempList = @()

    $filter_input_arr = $PSCompletions.filter_input_arr

    $config = scoop config
    $root_path = $config.root_path
    $global_path = $config.global_path

    switch ($filter_input_arr[0]) {
        'bucket' {
            switch ($filter_input_arr[1]) {
                'add' {
                    if ($filter_input_arr.Count -eq 2) {
                        foreach ($_ in scoop bucket known) {
                            $bucket = $_
                            $tempList += $PSCompletions.return_completion($bucket, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.bucket.add))
                        }
                    }
                }
                'rm' {
                    if ($filter_input_arr.Count -eq 2) {
                        foreach ($_ in Get-ChildItem "$root_path\buckets" 2>$null) {
                            $bucket = $_.Name
                            $tempList += $PSCompletions.return_completion($bucket, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.bucket.rm))
                        }
                    }
                }
            }
        }
        'uninstall' {
            if ($filter_input_arr.Count -gt 1) {
                $selected = $filter_input_arr[1..($filter_input_arr.Count - 1)]
            }
            else {
                $selected = @()
            }
            foreach ($_ in @("$root_path\apps", "$global_path\apps")) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $tempList += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.uninstall), @('SpaceTab'))
                    }
                }
            }
        }
        'update' {
            if ($filter_input_arr.Count -gt 1) {
                $selected = $filter_input_arr[1..($filter_input_arr.Count - 1)]
            }
            else {
                $selected = @()
            }
            foreach ($_ in @("$root_path\apps", "$global_path\apps")) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $tempList += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.update), @('SpaceTab'))
                    }
                }
            }
        }
        'cleanup' {
            if ($filter_input_arr.Count -gt 1) {
                $selected = $filter_input_arr[1..($filter_input_arr.Count - 1)]
            }
            else {
                $selected = @()
            }
            foreach ($_ in @("$root_path\apps", "$global_path\apps")) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $tempList += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cleanup), @('SpaceTab'))
                    }
                }
            }
        }
        'hold' {
            if ($filter_input_arr.Count -gt 1) {
                $selected = $filter_input_arr[1..($filter_input_arr.Count - 1)]
            }
            else {
                $selected = @()
            }
            foreach ($_ in @("$root_path\apps", "$global_path\apps")) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    $tempList += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.hold), @('SpaceTab'))
                }
            }
        }
        'unhold' {
            if ($filter_input_arr.Count -gt 1) {
                $selected = $filter_input_arr[1..($filter_input_arr.Count - 1)]
            }
            else {
                $selected = @()
            }
            foreach ($_ in @("$root_path\apps", "$global_path\apps")) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $tempList += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.unhold), @('SpaceTab'))
                    }
                }
            }
        }
        'prefix' {
            if ($filter_input_arr.Count -eq 1) {
                foreach ($_ in @("$root_path\apps", "$global_path\apps")) {
                    foreach ($item in (Get-ChildItem $_ 2>$null)) {
                        $app = $item.Name
                        $path = $item.FullName
                        $tempList += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.prefix))
                    }
                }
            }
        }
        'cache' {
            if ('*' -in $filter_input_arr) {
                break
            }
            if ($filter_input_arr.Count -ge 2 -and $filter_input_arr[1] -eq "rm") {
                $selected = $filter_input_arr[2..($filter_input_arr.Count - 1)]
                foreach ($_ in Get-ChildItem "$root_path\cache" -ErrorAction SilentlyContinue) {
                    $match = $_.BaseName -match '^([^#]+#[^#]+)'
                    if ($match) {
                        $part = $_.Name -split "#"
                        $path = $_.FullName
                        $cache = $part[0..1] -join "#"
                        if ($cache -notin $selected) {
                            $tempList += $PSCompletions.return_completion($cache, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cache.rm), @('SpaceTab'))
                        }
                    }
                }
            }
        }
        'config' {
            if ($filter_input_arr.Count -eq 1) {
                $configs = Get-Member -InputObject $config -MemberType NoteProperty
                $completions_list = $completions.CompletionText
                foreach ($c in $configs) {
                    $current_value = $c.Name
                    $info = $PSCompletions.completions_data.scoop.root.config.$($PSCompletions.guid).Where({ $_.CompletionText -eq $current_value })[0].ToolTip
                    if (!$info) {
                        $info = @($PSCompletions.info.current_value + ': ' + $current_value)
                    }
                    if ($current_value -notin $completions_list) {
                        $tempList += $PSCompletions.return_completion($current_value, $PSCompletions.replace_content($info))
                    }
                }
            }
        }
    }
    return $tempList + $completions
}
