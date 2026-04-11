function handleCompletions($completions) {
    $list = @()

    try {
        $config = scoop config
    }
    catch {
        return $completions
    }
    $root_path = $config.root_path
    $global_path = $config.global_path
    $config_path = "$root_path\config.json"
    if (Test-Path $config_path) {
        $PSCompletions._scoop_config_path = $config_path
    }
    else {
        $PSCompletions._scoop_config_path = "$home\.config\scoop\config.json"
    }

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude option parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    switch ($first_item) {
        'bucket' {
            switch ($filter_input_arr[1]) {
                'rm' {
                    if ($filter_input_arr.Count -eq 2) {
                        $items = Get-ChildItem "$root_path\buckets" 2>$null
                        foreach ($_ in $items) {
                            $bucket = $_.Name
                            $list += $PSCompletions.return_completion($bucket, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.bucket.rm))
                        }
                    }
                }
            }
        }
        'install' {
            if ($input_arr[-1] -in @('-a', '--arch')) {
                break
            }

            $PSCompletions.temp_scoop_installed_apps = Get-ChildItem "$root_path\apps" | ForEach-Object { $_.BaseName }

            $exclude_buckets = $PSCompletions.config.comp_config.scoop.exclude_buckets.Split('|')
            $dir = Get-ChildItem "$root_path\buckets" | ForEach-Object {
                if ($_.Name -in $exclude_buckets) {
                    return
                }
                @{
                    bucket = $_.BaseName
                    path   = "$($_.FullName)\bucket"
                }
            }
            $list += $PSCompletions.handle_data_by_runspace($dir, {
                    param ($items, $PSCompletions, $Host_UI)
                    $return = @()
                    foreach ($item in $items) {
                        Get-ChildItem $item.path -Recurse -Filter *.json | ForEach-Object {
                            $app = "$($item.bucket)/$($_.BaseName)"
                            if ($app -notin $PSCompletions.input_arr -and $_.BaseName -notin $PSCompletions.temp_scoop_installed_apps) {
                                if ($PSCompletions.config.comp_config[$PSCompletions.root_cmd].enable_hooks_tip -eq 0) {
                                    $tip = ''
                                }
                                else {
                                    $manifest_json = $_.FullName
                                    $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                                }
                                $return += @{
                                    ListItemText   = $app
                                    CompletionText = $app
                                    symbols        = @('SpaceTab')
                                    ToolTip        = $tip
                                }
                            }
                        }
                    }
                    return $return
                }, {
                    param($results)
                    return $results
                })

            <#
            使用 Scoop内部实现的 use_sqlite_cache 功能，查询数据库
            实测速度和直接遍历文件夹差不多
            # https://github.com/ScoopInstaller/Scoop/blob/master/libexec/scoop-search.ps1#L182
            #>

            # $scoopdir = $root_path
            # . "$scoopdir\apps\scoop\current\lib\database.ps1"
            # Select-ScoopDBItem $query -From @('name', 'binary', 'shortcut') |
            # Select-Object -Property name, version, bucket, binary |
            # ForEach-Object {
            #     $app = $_.bucket + "/" + $_.name
            #     $list += @{
            #         ListItemText   = $app
            #         CompletionText = $app
            #         symbols        = @("SpaceTab")
            #         # ToolTip        = $_.version # 不显示帮助信息，加快补全速度
            #     }
            # }
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
                    if ($app -eq 'scoop') { continue }
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $manifest_json = $path + '\current\manifest.json'
                        $install_json = $path + '\current\install.json'
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                        $list += $PSCompletions.return_completion($app, $tip, @('SpaceTab'))
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
                    if ($app -eq 'scoop') { continue }
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $manifest_json = $path + '\current\manifest.json'
                        $install_json = $path + '\current\install.json'
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                        $list += $PSCompletions.return_completion($app, $tip, @('SpaceTab'))
                    }
                }
            }
        }
        { $_ -in 'info', 'cat', 'reset' } {
            $exclude_buckets = $PSCompletions.config.comp_config.scoop.exclude_buckets.Split('|')
            $dir = Get-ChildItem "$root_path\buckets" | ForEach-Object {
                if ($_.Name -in $exclude_buckets) {
                    return
                }
                @{
                    bucket = $_.BaseName
                    path   = "$($_.FullName)\bucket"
                }
            }
            $list += $PSCompletions.handle_data_by_runspace($dir, {
                    param ($items, $PSCompletions, $Host_UI)
                    $return = @()
                    foreach ($item in $items) {
                        Get-ChildItem $item.path -Recurse -Filter *.json | ForEach-Object {
                            if ($_.BaseName -eq 'scoop') { continue }
                            $app = "$($item.bucket)/$($_.BaseName)"
                            if ($app -notin $PSCompletions.input_arr) {
                                if ($PSCompletions.config.comp_config[$PSCompletions.root_cmd].enable_hooks_tip -eq 0) {
                                    $tip = ''
                                }
                                else {
                                    $manifest_json = $_.FullName
                                    $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                                }
                                $return += @{
                                    ListItemText   = $app
                                    CompletionText = $app
                                    symbols        = @('SpaceTab')
                                    ToolTip        = $tip
                                }
                            }
                        }
                    }
                    return $return
                }, {
                    param($results)
                    return $results
                })
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
                    if ($app -eq 'scoop') { continue }
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $manifest_json = $path + '\current\manifest.json'
                        $install_json = $path + '\current\install.json'
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                        $list += $PSCompletions.return_completion($app, $tip, @('SpaceTab'))
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
                    if ($app -eq 'scoop') { continue }
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $manifest_json = $path + '\current\manifest.json'
                        $install_json = $path + '\current\install.json'
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                        $list += $PSCompletions.return_completion($app, $tip, @('SpaceTab'))
                    }
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
                    if ($app -eq 'scoop') { continue }
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $manifest_json = $path + '\current\manifest.json'
                        $install_json = $path + '\current\install.json'
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                        $list += $PSCompletions.return_completion($app, $tip, @('SpaceTab'))
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
                        $manifest_json = $path + '\current\manifest.json'
                        $install_json = $path + '\current\install.json'
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$type = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$type) { 'type:     ' + `$type; `"`n`" };
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; `"`n`" };
'version:  ' + `$c.version; `"`n`";
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.description) {
    '-----'; `"`n`";
    `$c.description.Replace(' | ', `"`n`")
};
}}
"@
                        if ($app -eq 'scoop') { $tip = ' ' }
                        $list += $PSCompletions.return_completion($app, $tip)
                    }
                }
            }
        }
        'cache' {
            if ('*' -in $filter_input_arr) {
                break
            }
            if ($filter_input_arr.Count -ge 2 -and $filter_input_arr[1] -eq 'rm') {
                $selected = $filter_input_arr[2..($filter_input_arr.Count - 1)]
                $items = Get-ChildItem "$root_path\cache" -ErrorAction SilentlyContinue
                foreach ($_ in $items) {
                    $match = $_.BaseName -match '^([^#]+#[^#]+)'
                    if ($match) {
                        $part = $_.Name -split '#'
                        $path = $_.FullName
                        $cache = $part[0..1] -join '#'
                        if ($cache -notin $selected) {
                            $list += $PSCompletions.return_completion($cache, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cache.rm), @('SpaceTab'))
                        }
                    }
                }
            }
        }
        'config' {
            if ($filter_input_arr[1] -eq 'rm') {
                foreach ($c in $config.PSObject.Properties.Name) {
                    $info = @($PSCompletions.info.current_value + ': ' + $config.$c)
                    $list += $PSCompletions.return_completion($c, $info)
                }
            }
        }
        'alias' {
            switch ($filter_input_arr[1]) {
                'rm' {
                    if ($filter_input_arr.Count -eq 2) {
                        foreach ($a in (Get-Member -InputObject (scoop config alias) -MemberType NoteProperty)) {
                            $list += $PSCompletions.return_completion($a.Name, ($a.Definition -replace '^.+=', ''))
                        }
                    }
                }
            }
        }
    }
    return $list + $completions
}
