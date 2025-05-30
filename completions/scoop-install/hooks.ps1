function handleCompletions($completions) {
    $tempList = @()

    $filter_input_arr = $PSCompletions.filter_input_arr


    # $PSCompletions.input_arr
    $config = scoop config
    $root_path = $config.root_path
    $global_path = $config.global_path

    if ($filter_input_arr.Count -eq 0) {
        $dir = @()
        $PSCompletions.temp_scoop_installed_apps = Get-ChildItem "$root_path\apps" | ForEach-Object { $_.BaseName }
        Get-ChildItem "$root_path\buckets" | ForEach-Object {
            $dir += @{
                bucket = $_.BaseName
                path   = "$($_.FullName)\bucket"
            }
        }
        $return = $PSCompletions.handle_data_by_runspace($dir, {
                param ($items, $PSCompletions, $Host_UI)
                $return = @()
                foreach ($item in $items) {
                    Get-ChildItem $item.path | ForEach-Object {
                        $app = "$($item.bucket)/$($_.BaseName)"
                        if ($app -notin $PSCompletions.input_arr -and $_.BaseName -notin $PSCompletions.temp_scoop_installed_apps) {
                            $return += @{
                                ListItemText   = $app
                                CompletionText = $app
                                symbols        = @()
                            }
                        }
                    }
                }
                return $return
            }, {
                param($results)
                return $results
            })
        $tempList += $return
    }
    elseif ($filter_input_arr[-1] -notlike '-*') {
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
            $paramList = @('64bit', '32bit', 'arm64')
            foreach ($param in $paramList) {
                $tempList += $PSCompletions.return_completion($param)
            }
        }
        else {
            if ($PSUICulture -eq 'zh-CN') {
                $tips_cn = @{
                    '-g'                = "U: -g|--global`n全局安装程序"
                    '--global'          = "U: -g|--global`n全局安装程序"
                    '-i'                = "U: -i|--independent`n不自动安装依赖项"
                    '--independent'     = "U: -i|--independent`n不自动安装依赖项"
                    '-k'                = "U: -k|--no-cache`n不使用下载缓存"
                    '--no-cache'        = "U: -k|--no-cache`n不使用下载缓存"
                    '-s'                = "U: -s|--skip-hash-check`n跳过哈希验证(使用时请谨慎!)"
                    '--skip-hash-check' = "U: -s|--skip-hash-check`n跳过哈希验证(使用时请谨慎!)"
                    '-u'                = "U: -u|--no-update-scoop`n安装之前不更新 Scoop，如果它已过时"
                    '--no-update-scoop' = "U: -u|--no-update-scoop`n安装之前不更新 Scoop，如果它已过时"
                    '-a'                = "U: -a|--arch`n使用指定的体系结构，如果程序支持"
                    '--arch'            = "U: -a|--arch`n使用指定的体系结构，如果程序支持"
                }
                foreach ($param in $paramList) {
                    $shouldAdd = $true
                    if ($param -in $PSCompletions.input_arr -or $paramAliases[$param] -in $PSCompletions.input_arr) {
                        $shouldAdd = $false
                    }
                    if ($shouldAdd) {
                        $symbol = if ($param -in @('-a', '--arch')) { @('SpaceTab') } else { @('OptionTab') }
                        $tempList += $PSCompletions.return_completion($param, $tips_cn[$param], $symbol)
                    }
                }
            }
            else {
                $tips_en = @{
                    '-g'                = "U: -g|--global`nInstall the app globally."
                    '--global'          = "U: -g|--global`nInstall the app globally."
                    '-i'                = "U: -i|--independent`nDon't install dependencies automatically."
                    '--independent'     = "U: -i|--independent`nDon't install dependencies automatically."
                    '-k'                = "U: -k|--no-cache`nDon't use the download cache."
                    '--no-cache'        = "U: -k|--no-cache`nDon't use the download cache."
                    '-s'                = "U: -s|--skip-hash-check`nSkip hash validation (use with caution!)."
                    '--skip-hash-check' = "U: -s|--skip-hash-check`nSkip hash validation (use with caution!)."
                    '-u'                = "U: -u|--no-update-scoop`nDon't update Scoop before installing if it's outdated."
                    '--no-update-scoop' = "U: -u|--no-update-scoop`nDon't update Scoop before installing if it's outdated."
                    '-a'                = "U: -a|--arch`nUse the specified architecture, if the app supports it."
                    '--arch'            = "U: -a|--arch`nUse the specified architecture, if the app supports it."
                }
                foreach ($param in $paramList) {
                    $shouldAdd = $true
                    if ($param -in $PSCompletions.input_arr -or $paramAliases[$param] -in $PSCompletions.input_arr) {
                        $shouldAdd = $false
                    }
                    if ($shouldAdd) {
                        $symbol = if ($param -in @('-a', '--arch')) { @('SpaceTab') } else { @('OptionTab') }
                        $tempList += $PSCompletions.return_completion($param, $tips_cn[$param], $symbol)
                    }
                    # if ($param -notin $PSCompletions.input_arr) {
                    #     $symbol = if ($param -in @('-a', '--arch')) { @('SpaceTab') } else { @('OptionTab') }
                    #     $tempList += $PSCompletions.return_completion($param, $tips_cn[$param], $symbol)
                    # }
                }
            }
        }
    }
    return $tempList + $completions
}
