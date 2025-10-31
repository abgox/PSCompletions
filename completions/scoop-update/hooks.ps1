function handleCompletions($completions) {
    $tempList = @()

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
    $tempList += $PSCompletions.return_completion('-reset', $resetTip, @('OptionTab'))

    if ($filter_input_arr[-1] -notlike '-*') {
        $paramList = @(
            '-f', '--force',
            '-g', '--global',
            '-i', '--independent',
            '-k', '--no-cache',
            '-s', '--skip-hash-check',
            '-q', '--quiet',
            '-a', '--all'
        )
        $paramAliases = @{
            '-f'                = '--force'
            '--force'           = '-f'
            '-g'                = '--global'
            '--global'          = '-g'
            '-i'                = '--independent'
            '--independent'     = '-i'
            '-k'                = '--no-cache'
            '--no-cache'        = '-k'
            '-s'                = '--skip-hash-check'
            '--skip-hash-check' = '-s'
            '-q'                = '--quiet'
            '--quiet'           = '-q'
            '-a'                = '--all'
            '--all'             = '-a'
        }

        if ($CN) {
            $tips = @{
                '-f'                = "U: -f, --force`n即使没有新版本也强制更新`n它可以实现重装的效果"
                '--force'           = "U: -f, --force`n即使没有新版本也强制更新`n它可以实现重装的效果"
                '-g'                = "U: -g, --global`n全局更新程序"
                '--global'          = "U: -g, --global`n全局更新程序"
                '-i'                = "U: -i, --independent`n不自动安装依赖项"
                '--independent'     = "U: -i, --independent`n不自动安装依赖项"
                '-k'                = "U: -k, --no-cache`n不使用下载缓存"
                '--no-cache'        = "U: -k, --no-cache`n不使用下载缓存"
                '-s'                = "U: -s, --skip-hash-check`n跳过哈希验证(使用时请谨慎!)"
                '--skip-hash-check' = "U: -s, --skip-hash-check`n跳过哈希验证(使用时请谨慎!)"
                '-q'                = "U: -q, --quiet`n安静模式，隐藏无关信息"
                '--quiet'           = "U: -q, --quiet`n安静模式，隐藏无关信息"
                '-a'                = "U: -a, --all`n更新所有已安装的程序，等同于 *"
                '--all'             = "U: -a, --all`n更新所有已安装的程序，等同于 *"
            }
        }
        else {
            $tips = @{
                '-f'                = "U: -f, --force`nForce update even when there isn't a newer version."
                '--force'           = "U: -f, --force`nForce update even when there isn't a newer version."
                '-g'                = "U: -g, --global`nUpdate the app globally."
                '--global'          = "U: -g, --global`nUpdate the app globally."
                '-i'                = "U: -i, --independent`nDon't install dependencies automatically."
                '--independent'     = "U: -i, --independent`nDon't install dependencies automatically."
                '-k'                = "U: -k, --no-cache`nDon't use the download cache."
                '--no-cache'        = "U: -k, --no-cache`nDon't use the download cache."
                '-s'                = "U: -s, --skip-hash-check`nSkip hash validation (use with caution!)."
                '--skip-hash-check' = "U: -s, --skip-hash-check`nSkip hash validation (use with caution!)."
                '-q'                = "U: -q, --quiet`nHide extraneous messages."
                '--quiet'           = "U: -q, --quiet`nHide extraneous messages."
                '-a'                = "U: -a, --all`nUpdate all apps (alternative to '*')"
                '--all'             = "U: -a, --all`nUpdate all apps (alternative to '*')"
            }
        }
        foreach ($param in $paramList) {
            $shouldAdd = $true
            if ($param -in $PSCompletions.input_arr -or $paramAliases[$param] -in $PSCompletions.input_arr) {
                $shouldAdd = $false
            }
            if ($shouldAdd) {
                $tempList += $PSCompletions.return_completion($param, $tips[$param], @('OptionTab'))
            }
        }
    }

    if ($addApp) {
        foreach ($_ in @("$root_path\apps", "$global_path\apps")) {
            foreach ($item in (Get-ChildItem $_ 2>$null)) {
                $app = $item.Name
                $path = $item.FullName
                if ($app -notin $PSCompletions.input_arr) {
                    $tempList += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.update), @('SpaceTab'))
                }
            }
        }
    }

    return $tempList + $completions
}
