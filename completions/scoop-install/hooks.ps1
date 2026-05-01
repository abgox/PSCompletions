function handleCompletions($completions) {
    $list = @()

    try {
        $config = scoop config
    }
    catch {
        return $completions
    }
    $CN = $PSUICulture -like 'zh*'
    $root_path = $env:SCOOP, $config.root_path | Select-Object -First 1
    if (-not $root_path) {
        if ($CN) {
            throw 'Scoop 未配置 root_path, 请先进行配置: scoop config root_path <scoop_path>'
        }
        else {
            throw 'Scoop does not have a root_path configuration. Please set it first: scoop config root_path <scoop_path>'
        }
    }
    $global_path = $env:SCOOP_GLOBAL, $config.global_path | Select-Object -First 1
    $apps_dir = "$root_path\apps", "$global_path\apps" | Where-Object { Test-Path $_ }
    $buckets_dir = "$root_path\buckets"

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude option parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    # 是否需要添加应用补全
    $addApp = $true

    if ($last_item -notlike '-*') {
        $paramList = @(
            '-g', '--global',
            '-i', '--independent',
            '-k', '--no-cache',
            '-s', '--skip-hash-check',
            '-u', '--no-update-scoop',
            '-a', '--arch'
        )
        $paramAliases = @{
            '-g'                = '--global'
            '--global'          = '-g'
            '-i'                = '--independent'
            '--independent'     = '-i'
            '-k'                = '--no-cache'
            '--no-cache'        = '-k'
            '-s'                = '--skip-hash-check'
            '--skip-hash-check' = '-s'
            '-u'                = '--no-update-scoop'
            '--no-update-scoop' = '-u'
            '-a'                = '--arch'
            '--arch'            = '-a'
        }

        if ($input_arr[-1] -in @('-a', '--arch')) {
            $addApp = $false
            $paramList = @('64bit', '32bit', 'arm64')
            foreach ($param in $paramList) {
                $list += $PSCompletions.return_completion($param)
            }
        }
        else {
            if ($CN) {
                $tips = @{
                    '-g'                = "U: -g, --global`n全局安装程序"
                    '--global'          = "U: -g, --global`n全局安装程序"
                    '-i'                = "U: -i, --independent`n不自动安装依赖项"
                    '--independent'     = "U: -i, --independent`n不自动安装依赖项"
                    '-k'                = "U: -k, --no-cache`n不使用下载缓存"
                    '--no-cache'        = "U: -k, --no-cache`n不使用下载缓存"
                    '-s'                = "U: -s, --skip-hash-check`n跳过哈希验证(使用时请谨慎!)"
                    '--skip-hash-check' = "U: -s, --skip-hash-check`n跳过哈希验证(使用时请谨慎!)"
                    '-u'                = "U: -u, --no-update-scoop`n安装之前不更新 Scoop，如果它已过时"
                    '--no-update-scoop' = "U: -u, --no-update-scoop`n安装之前不更新 Scoop，如果它已过时"
                    '-a'                = "U: -a, --arch`n使用指定的体系结构，如果程序支持"
                    '--arch'            = "U: -a, --arch`n使用指定的体系结构，如果程序支持"
                }
            }
            else {
                $tips = @{
                    '-g'                = "U: -g, --global`nInstall the app globally."
                    '--global'          = "U: -g, --global`nInstall the app globally."
                    '-i'                = "U: -i, --independent`nDon't install dependencies automatically."
                    '--independent'     = "U: -i, --independent`nDon't install dependencies automatically."
                    '-k'                = "U: -k, --no-cache`nDon't use the download cache."
                    '--no-cache'        = "U: -k, --no-cache`nDon't use the download cache."
                    '-s'                = "U: -s, --skip-hash-check`nSkip hash validation (use with caution!)."
                    '--skip-hash-check' = "U: -s, --skip-hash-check`nSkip hash validation (use with caution!)."
                    '-u'                = "U: -u, --no-update-scoop`nDon't update Scoop before installing if it's outdated."
                    '--no-update-scoop' = "U: -u, --no-update-scoop`nDon't update Scoop before installing if it's outdated."
                    '-a'                = "U: -a, --arch`nUse the specified architecture, if the app supports it."
                    '--arch'            = "U: -a, --arch`nUse the specified architecture, if the app supports it."
                }
            }
            foreach ($param in $paramList) {
                $shouldAdd = $true
                if ($param -in $input_arr -or $paramAliases[$param] -in $input_arr) {
                    $shouldAdd = $false
                }
                if ($shouldAdd) {
                    $symbol = if ($param -in @('-a', '--arch')) { @('SpaceTab') } else { @('OptionTab') }
                    $list += $PSCompletions.return_completion($param, $tips[$param], $symbol)
                }
            }
        }
    }

    if ($addApp) {
        $PSCompletions.temp_scoop_installed_apps = $apps_dir | ForEach-Object { Get-ChildItem $_ | ForEach-Object { $_.BaseName } }
        $dir = Get-ChildItem $buckets_dir | ForEach-Object {
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
'version:  ' + `$c.version; `"`n`";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; `"`n`" };
'homepage: ' + `$c.homepage; `"`n`";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)(A-New-LinkFile|A-New-LinkDirectory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); `"`n`"; }
if (`$c.admin){ 'permissions: admin'; `"`n`"; }
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

    return $list + $completions
}
