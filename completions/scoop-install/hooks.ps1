function handleCompletions($completions) {
    $list = @()

    $filter_input_arr = $PSCompletions.filter_input_arr

    # $PSCompletions.input_arr
    try {
        $config = scoop config
    }
    catch {
        return $completions
    }
    $root_path = $config.root_path
    $global_path = $config.global_path
    $CN = $PSUICulture -like 'zh*'

    # 是否需要添加应用补全
    $addApp = $true

    if ($CN) {
        $resetTip = "撤销所有 Scoop bucket 中的本地文件更改`n通过 git stash 命令实现"
    }
    else {
        $resetTip = "Undo all local file changes in Scoop buckets.`nIt use 'git stash'"
    }
    $list += $PSCompletions.return_completion('-reset', $resetTip, @('OptionTab'))

    if ($filter_input_arr[-1] -notlike '-*') {
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

        if ($PSCompletions.input_arr[-1] -in @('-a', '--arch')) {
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
                if ($param -in $PSCompletions.input_arr -or $paramAliases[$param] -in $PSCompletions.input_arr) {
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
        $PSCompletions.temp_scoop_installed_apps = Get-ChildItem "$root_path\apps" | ForEach-Object { $_.BaseName }
        $dir = Get-ChildItem "$root_path\buckets" | ForEach-Object {
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
                            $return += @{
                                ListItemText   = $app
                                CompletionText = $app
                                symbols        = @("SpaceTab")
                                ToolTip        = "{{ `$c = (Get-Content $($_.FullName) | ConvertFrom-Json); `$c.homepage; `"`n`"; `$c.description.Replace(' | ', `"`n`") }}"
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
