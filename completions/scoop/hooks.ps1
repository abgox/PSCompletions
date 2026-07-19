function handleCompletions($completions) {
    if ($PSCompletions.pending.text -like '-*') {
        return $completions
    }
    try {
        $config = scoop config
    }
    catch {
        return $completions
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $tokens = @($PSCompletions.tokens)
    $tokens_text = @($tokens.text)
    $cmds = @($tokens | Where-Object type -EQ 'command')
    # $cmds_text = @($cmds.text)
    $opts = @($tokens | Where-Object type -EQ 'option')
    # $opts_text = @($opts.text)
    $unknown = @($tokens | Where-Object type -EQ 'unknown')
    $unknown_text = @($unknown.text)
    function add {
        param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
        if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text)*"))) { return }
        $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    }

    function add2 {
        param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
        if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text -replace '.+[/\\]', '')*"))) { return }
        $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    }

    $root_path = $env:SCOOP, $config.root_path | Select-Object -First 1
    if (-not $root_path) {
        throw $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.warning.config)
    }
    $global_path = $env:SCOOP_GLOBAL, $config.global_path | Select-Object -First 1
    $apps_dir = "$root_path\apps", "$global_path\apps" | Where-Object { Test-Path -LiteralPath $_ }
    $buckets_dir = "$root_path\buckets"

    $config_path = "$root_path\config.json"
    if (Test-Path -LiteralPath $config_path) {
        $PSCompletions._scoop_config_path = $config_path
    }
    else {
        $PSCompletions._scoop_config_path = "$home\.config\scoop\config.json"
    }

    switch ($cmds[0].text) {
        'bucket' {
            switch ($cmds[1].text) {
                'rm' {
                    $items = Get-ChildItem $buckets_dir 2>$null
                    foreach ($_ in $items) {
                        add $_.Name $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.bucket.rm)
                    }
                }
            }
        }
        'install' {
            if ($tokens[-1].text -in '-a', '--arch') {
                break
            }

            $PSCompletions.temp_scoop_installed_apps = $apps_dir | ForEach-Object { Get-ChildItem $_ | ForEach-Object { $_.BaseName } }

            $exclude_buckets = $PSCompletions.config.completion.scoop.exclude_buckets -split '\|'
            $dir = Get-ChildItem $buckets_dir | ForEach-Object {
                if ($_.Name -in $exclude_buckets) {
                    return
                }
                @{
                    bucket = $_.BaseName
                    path   = "$($_.FullName)\bucket"
                }
            }
            $_ = $PSCompletions.handle_data_by_runspace($dir, {
                    param ($items, $PSCompletions, $Host_UI)
                    $return = @()
                    $tokens_text = $PSCompletions.tokens.text
                    foreach ($item in $items) {
                        Get-ChildItem $item.path -Recurse -File -Filter *.json | ForEach-Object {
                            if ($_.BaseName -eq 'scoop' -or $_.BaseName -in $PSCompletions.temp_scoop_installed_apps) { return }
                            $app = "$($item.bucket)/$($_.BaseName)"
                            if ($app -in $tokens_text) { return }
                            if ($PSCompletions.pending.text -and ($_.BaseName -notlike "$($PSCompletions.pending.text)*" -and $app -notlike "$($PSCompletions.pending.text)*")) { return }
                            if ($PSCompletions.config.completion[$PSCompletions.cmd].enable_hooks_tip -eq 0) {
                                $tip = ''
                            }
                            else {
                                $manifest_json = $_.FullName
                                $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
'version:  ' + `$c.version; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
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
                    return $return
                }, {
                    param($results)
                    return $results
                })
            if ($_) { $list.AddRange(@($_)) }

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
            #     $list.Add(@{
            #         ListItemText   = $app
            #         CompletionText = $app
            #         symbols        = @("SpaceTab")
            #         # ToolTip        = $_.version # 不显示帮助信息，加快补全速度
            #     })
            # }
        }
        'uninstall' {
            foreach ($_ in $apps_dir) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    if ($app -eq 'scoop' -or $app -in $unknown_text) { continue }
                    $path = $item.FullName
                    $manifest_json = $path + '\current\manifest.json'
                    $install_json = $path + '\current\install.json'
                    $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; "`n" };
'version:  ' + `$c.version; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
};
}}
"@
                    add2 $app $tip @('SpaceTab')
                }
            }
        }
        { $_ -in 'update', 'depends' } {
            foreach ($_ in $apps_dir) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    if ($app -eq 'scoop' -or $app -in $unknown_text) { continue }
                    $path = $item.FullName
                    $manifest_json = $path + '\current\manifest.json'
                    $install_json = $path + '\current\install.json'
                    $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json;
`$b = `$i.bucket;
if (`$b) { 'bucket:   ' + `$b; "`n" };
`$v = "$root_path\buckets\`$b\bucket\$($app[0])\$($app.Split('.', 2)[0])\$app.json", "$root_path\buckets\`$b\bucket\$app.json" |
ForEach-Object { (Get-Content `$_ -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json).version } |
Select-Object -First 1;
`$new = if (`$v -and `$v -ne `$c.version) { " (`$v)" } else { '' };
'version:  ' + `$c.version + `$new; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
};
}}
"@
                    add2 $app $tip @('SpaceTab')
                }
            }
        }
        { $_ -in 'home', 'info', 'cat', 'reset', 'download', 'virustotal' } {
            $exclude_buckets = $PSCompletions.config.completion.scoop.exclude_buckets -split '\|'
            $dir = Get-ChildItem $buckets_dir | ForEach-Object {
                if ($_.Name -in $exclude_buckets) {
                    return
                }
                @{
                    bucket = $_.BaseName
                    path   = "$($_.FullName)\bucket"
                }
            }
            $_ = $PSCompletions.handle_data_by_runspace($dir, {
                    param ($items, $PSCompletions, $Host_UI)
                    $return = @()
                    $tokens_text = $PSCompletions.tokens.text
                    foreach ($item in $items) {
                        Get-ChildItem $item.path -Recurse -File -Filter *.json | ForEach-Object {
                            if ($_.BaseName -eq 'scoop') { return }
                            $app = "$($item.bucket)/$($_.BaseName)"
                            if ($app -in $tokens_text) { return }
                            if ($PSCompletions.pending.text -and ($_.BaseName -notlike "$($PSCompletions.pending.text)*" -and $app -notlike "$($PSCompletions.pending.text)*")) { return }
                            if ($PSCompletions.config.completion[$PSCompletions.cmd].enable_hooks_tip -eq 0) {
                                $tip = ''
                            }
                            else {
                                $manifest_json = $_.FullName
                                $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
'version:  ' + `$c.version; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
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
                    return $return
                }, {
                    param($results)
                    return $results
                })
            if ($_) { $list.AddRange(@($_)) }
        }
        'cleanup' {
            foreach ($_ in $apps_dir) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    if ($app -eq 'scoop' -or $app -in $unknown_text) { continue }
                    $path = $item.FullName
                    $manifest_json = $path + '\current\manifest.json'
                    $install_json = $path + '\current\install.json'
                    $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; "`n" };
'version:  ' + `$c.version; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
};
}}
"@
                    add2 $app $tip @('SpaceTab')
                }
            }
        }
        'hold' {
            foreach ($_ in $apps_dir) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    if ($app -eq 'scoop' -or $app -in $unknown_text) { continue }
                    $path = $item.FullName
                    $manifest_json = $path + '\current\manifest.json'
                    $install_json = $path + '\current\install.json'
                    if (-not (Get-Content -Raw $install_json -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json).hold) {
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json;
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; "`n" };
'version:  ' + `$c.version; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
};
}}
"@
                        add2 $app $tip @('SpaceTab')
                    }
                }
            }
        }
        'unhold' {
            foreach ($_ in $apps_dir) {
                foreach ($item in (Get-ChildItem $_ 2>$null)) {
                    $app = $item.Name
                    if ($app -eq 'scoop' -or $app -in $unknown_text) { continue }
                    $path = $item.FullName
                    $manifest_json = $path + '\current\manifest.json'
                    $install_json = $path + '\current\install.json'
                    if ((Get-Content -Raw $install_json -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json).hold) {
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; "`n" };
'version:  ' + `$c.version; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
};
}}
"@
                        add2 $app $tip @('SpaceTab')
                    }
                }
            }
        }
        'prefix' {
            if ($cmds.Count -eq 1) {
                foreach ($_ in $apps_dir) {
                    foreach ($item in (Get-ChildItem $_ 2>$null)) {
                        $app = $item.Name
                        $path = $item.FullName
                        $manifest_json = $path + '\current\manifest.json'
                        $install_json = $path + '\current\install.json'
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
if (`$i.bucket) { 'bucket:   ' + `$i.bucket; "`n" };
'version:  ' + `$c.version; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
};
}}
"@
                        if ($app -eq 'scoop') { $tip = ' ' }
                        add2 $app $tip
                    }
                }
            }
        }
        'cache' {
            if ('*' -in $tokens_text -or $cmds[1].text -ne 'rm') {
                break
            }
            $items = "$root_path\cache", $config.cache_path | ForEach-Object { if ($_) { Get-ChildItem $_ -ErrorAction SilentlyContinue } }
            foreach ($_ in $items) {
                $match = $_.BaseName -match '^([^#]+#[^#]+)'
                if ($match) {
                    $part = $_.Name -split '#'
                    $path = $_.FullName
                    $cache = $part[0..1] -join '#'
                    if ($cache -in $unknown_text) { continue }
                    add $cache $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cache.rm) @('SpaceTab')
                }
            }
        }
        'config' {
            if ($cmds[1].text -ne 'rm') {
                break
            }
            foreach ($c in $config.PSObject.Properties.Name) {
                add $c @($PSCompletions.info.current_value + ': ' + $config.$c)
            }
        }
    }
    return $list + $completions
}
