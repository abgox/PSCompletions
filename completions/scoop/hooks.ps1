function handleCompletions($completions) {
    $list = @()

    $filter_input_arr = $PSCompletions.filter_input_arr

    try {
        $config = scoop config
    }
    catch {
        return $completions
    }
    $root_path = $config.root_path
    $global_path = $config.global_path

    switch ($filter_input_arr[0]) {
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
                                $return += @{
                                    ListItemText   = $app
                                    CompletionText = $app
                                    symbols        = @("SpaceTab")
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
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $list += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.uninstall), @('SpaceTab'))
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
                        $list += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.update), @('SpaceTab'))
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
                            $app = "$($item.bucket)/$($_.BaseName)"
                            if ($app -notin $PSCompletions.input_arr) {
                                $return += @{
                                    ListItemText   = $app
                                    CompletionText = $app
                                    symbols        = @("SpaceTab")
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
                    $path = $item.FullName
                    if ($app -notin $selected) {
                        $list += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cleanup), @('SpaceTab'))
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
                    $list += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.hold), @('SpaceTab'))
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
                        $list += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.unhold), @('SpaceTab'))
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
                        $list += $PSCompletions.return_completion($app, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.prefix))
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
                $items = Get-ChildItem "$root_path\cache" -ErrorAction SilentlyContinue
                foreach ($_ in $items) {
                    $match = $_.BaseName -match '^([^#]+#[^#]+)'
                    if ($match) {
                        $part = $_.Name -split "#"
                        $path = $_.FullName
                        $cache = $part[0..1] -join "#"
                        if ($cache -notin $selected) {
                            $list += $PSCompletions.return_completion($cache, $PSCompletions.replace_content($PSCompletions.completions.scoop.info.tip.cache.rm), @('SpaceTab'))
                        }
                    }
                }
            }
        }
        'config' {
            $configList = [PSCustomObject]@{
                'use_external_7zip'                    = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'External 7zip (from path) will be used for archives extraction.')
                    'zh-CN' = @('默认值: false', '使用外部的 7zip(从路径)来解压缩。')
                }
                'use_lessmsi'                          = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'Prefer lessmsi utility over native msiexec.')
                    'zh-CN' = @('默认值: false', '使用 lessmsi 代替原生的 msiexec。')
                }
                'use_sqlite_cache'                     = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'Use SQLite database for caching. ', 'This is useful for speeding up ''scoop search'' and ''scoop shim'' commands.')
                    'zh-CN' = @('默认值: false', '使用 SQLite 数据库缓存。', '这对于提升 scoop search 和 scoop shim 命令的速度有帮助。')
                }
                'no_junction'                          = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'The ''current'' version alias will not be used. ', 'Shims and shortcuts will point to specific version instead.', 'It seems to be causing some issues, so it''s not recommended to use it.')
                    'zh-CN' = @('默认值: false', '不使用 current 版本别名。Shims 和快捷方式将指向具体版本。', '它似乎有点问题，不建议使用')
                }
                'scoop_repo'                           = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: http://github.com/ScoopInstaller/Scoop', 'Git repository containining scoop source code.', 'This configuration is useful for custom forks.')
                    'zh-CN' = @('默认值: http://github.com/ScoopInstaller/Scoop', 'Scoop 源代码仓库', '对于自定义分支很有用。')
                }
                'scoop_branch'                         = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Allow to use different branch than master.', 'Could be used for testing specific functionalities before released into all users.', 'If you want to receive updates earlier to test new functionalities use develop')
                    'zh-CN' = @('允许使用与 master 分支不同的分支。', '这对于测试特定功能的早期更新很有用。', '如果您想更早地接收更新以测试新功能，请使用 develop')
                }
                'proxy'                                = @{
                    symbol  = ''
                    'en-US' = @('By default, Scoop will use the proxy settings from Internet Options, but with anonymous authentication.')
                    'zh-CN' = @('默认情况下，Scoop 会使用 Internet 选项中的代理设置，但使用匿名身份验证。')
                }
                'autostash_on_conflict'                = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'When a conflict is detected during updating, Scoop will auto-stash the uncommitted changes.', 'Default is false, which will abort the update')
                    'zh-CN' = @('默认值: false', '当更新发生冲突时，Scoop 会自动暂存未提交的更改。', '默认是 false，这将中止更新')
                }
                'default_architecture'                 = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Allow to configure preferred architecture for application installation.', 'If not specified, architecture is determined by system.')
                    'zh-CN' = @('允许配置软件安装的首选架构。', '如果没有指定，架构将由系统决定。')
                }
                'debug'                                = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'Additional and detailed output will be shown.')
                    'zh-CN' = @('默认值: false', '显示额外的详细输出。')
                }
                'force_update'                         = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'Force apps updating to bucket''s version.')
                    'zh-CN' = @('默认值: false', '强制更新到 bucket 的版本。')
                }
                'show_update_log'                      = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: true', 'Show changed commits on ''scoop update''')
                    'zh-CN' = @('默认值: true', '显示 scoop update 时的变更记录')
                }
                'show_manifest'                        = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'Displays the manifest of every app that''s about to be installed, then asks user if they wish to proceed.')
                    'zh-CN' = @('默认值: false', '显示将要安装的每个应用的清单，然后询问用户是否继续。')
                }
                'shim'                                 = @{
                    symbol  = ''
                    'en-US' = @('Choose scoop shim build.')
                    'zh-CN' = @('选择 scoop shim 构建。')
                }
                'root_path'                            = @{
                    symbol  = ''
                    'en-US' = @('Path to Scoop root directory.')
                    'zh-CN' = @('Scoop 根目录路径。')
                }
                'global_path'                          = @{
                    symbol  = ''
                    'en-US' = @('Path to Scoop root directory for global apps.')
                    'zh-CN' = @('Scoop 全局应用目录路径。')
                }
                'cache_path'                           = @{
                    symbol  = ''
                    'en-US' = @('For downloads, defaults to ''cache'' folder under Scoop root directory.')
                    'zh-CN' = @('下载的默认路径，默认为 Scoop 根目录下的 cache 文件夹。')
                }
                'gh_token'                             = @{
                    symbol  = ''
                    'en-US' = @('GitHub API token used to make authenticated requests.', 'This is essential for checkver and similar functions to run without incurring rate limits and download from private repositories.')
                    'zh-CN' = @('GitHub API 令牌，用于进行认证请求。', '这对于 checkver 等功能运行而不受速率限制和下载私有仓库有帮助。')
                }
                'virustotal_api_key'                   = @{
                    symbol  = ''
                    'en-US' = @('API key used for uploading/scanning files using virustotal.')
                    'zh-CN' = @('VirusTotal API 密钥，用于上传/扫描文件。')
                }
                'cat_style'                            = @{
                    symbol  = ''
                    'en-US' = @('When set to a non-empty string, Scoop will use ''bat'' to display the manifest for the `scoop cat` command and while doing manifest review.', 'This requires ''bat'' to be installed (run `scoop install bat` to install it), otherwise errors will be thrown.', 'The accepted values are the same as ones passed to the --style flag of ''bat''.')
                    'zh-CN' = @('当设置为非空字符串时，Scoop 将使用 bat 来显示 manifest 信息，并在进行清单审核时使用。', '这需要 bat 已安装（运行 scoop install bat 来安装它），否则会报错。', '接受的值与 bat 的 --style 标志相同。')
                }
                'ignore_running_processes'             = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'When set to false (default), Scoop would stop its procedure immediately if it detects any target app process is running.', 'Procedure here refers to reset/uninstall/update.', 'When set to true, Scoop only displays a warning message and continues procedure.')
                    'zh-CN' = @('默认值: false', '当设置为 false 时，Scoop 会在检测到目标应用进程正在运行时立即停止其过程。', '这里的过程指的是 reset/uninstall/update。', '当设置为 true 时，Scoop 只显示警告信息，并继续过程。')
                }
                'private_hosts'                        = @{
                    symbol  = ''
                    'en-US' = @('Array of private hosts that need additional authentication.', 'For example, if you want to access a private GitHub repository, you need to add the host to this list with ''match'' and ''headers'' strings.')
                    'zh-CN' = @('私有主机数组，需要额外的身份验证。', '例如，如果要访问私有 GitHub 仓库，则需要将主机添加到此列表中，并使用 ''match'' 和 ''headers'' 字符串。')
                }
                'hold_update_until'                    = @{
                    symbol  = ''
                    'en-US' = @('Disable/Hold Scoop self-updates, until the specified date.', '`scoop hold scoop` will set the value to one day later.', 'Should be in the format ''YYYY-MM-DD'', ''YYYY/MM/DD'' or any other forms that accepted by ''[System.DateTime]::Parse()''.')
                    'zh-CN' = @('禁用/暂停 Scoop 自更新，直到指定日期。', 'scoop hold scoop 将值设置为一天后。', '应该使用 ''YYYY-MM-DD''、''YYYY/MM/DD'' 或其他接受的格式来指定。')
                }
                'update_nightly'                       = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'Nightly version is formatted as ''nightly-yyyyMMdd'' and will be updated after one day if this is set to true.', 'Otherwise, nightly version will not be updated unless `--force` is used.')
                    'zh-CN' = @('默认值: false', 'Nightly 版本以 ''nightly-yyyyMMdd'' 格式显示，如果设置为 true，则每天更新一次。', '否则，nightly 版本不会更新，除非使用 --force。')
                }
                'use_isolated_path'                    = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'When set to true, Scoop will use `SCOOP_PATH` environment variable to store apps'' `PATH`s.', 'When set to arbitrary non-empty string, Scoop will use that string as the environment variable name instead.', 'This is useful when you want to isolate Scoop from the system `PATH`.')
                    'zh-CN' = @('默认值: false', '当设置为 true 时，Scoop 将使用 SCOOP_PATH 环境变量来存储应用的 PATH。', '当设置为任意非空字符串时，Scoop 将使用该字符串作为环境变量名。', '这对于隔离 Scoop 与系统 PATH 有用。')
                }
                'aria2-enabled'                        = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: false', 'Aria2 will be used for downloading of artifacts.')
                    'zh-CN' = @('默认值: false', '使用 Aria2 进行下载。')
                }
                'aria2-warning-enabled'                = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: true', 'Enable Aria2c warning which is shown while downloading.')
                    'zh-CN' = @('默认值: true', '启用 Aria2 下载时的警告。')
                }
                'aria2-retry-wait'                     = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: 2', 'Number of seconds to wait between retries.')
                    'zh-CN' = @('默认值: 2', '重试等待时间。')
                }
                'aria2-split'                          = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: 5', 'Number of connections used for downlaod.')
                    'zh-CN' = @('默认值: 5', '下载使用的连接数。')
                }
                'aria2-max-connection-per-server'      = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: 5', 'The maximum number of connections to one server for each download.')
                    'zh-CN' = @('默认值: 5', '每个服务器的最大连接数。')
                }
                'aria2-min-split-size'                 = @{
                    symbol  = 'SpaceTab'
                    'en-US' = @('Default Value: 5M', 'Downloaded files will be splitted by this configured size and downloaded using multiple connections.')
                    'zh-CN' = @('默认值: 5M', '下载的文件将根据此配置大小进行分割，并使用多个连接下载。')
                }
                'aria2-options'                        = @{
                    symbol  = ''
                    'en-US' = @('Array of additional aria2 options.')
                    'zh-CN' = @('aria2 选项数组。')
                }

                # abyss bucket config
                'abgox-abyss-app-uninstall-action'     = @{
                    symbol  = 'SpaceTab'
                    'zh-CN' = @('默认值: 1', '应用卸载操作行为。', '它是 abyss bucket (https://gitee.com/abgox/abyss) 中的一个配置项', '详情参考: https://gitee.com/abgox/abyss#config')
                    'en-US' = @('Default Value: 1', 'The action of app uninstall.', 'It is a config in abyss bucket (https://github.com/abgox/abyss).', 'See https://github.com/abgox/abyss#config for details.')
                }
                'abgox-abyss-app-shortcuts-action'     = @{
                    symbol  = 'SpaceTab'
                    'zh-CN' = @('默认值: 1', '快捷方式的创建行为。', '它是 abyss bucket (https://gitee.com/abgox/abyss) 中的一个配置项', '详情参考: https://gitee.com/abgox/abyss#config')
                    'en-US' = @('Default Value: 1', 'The action of shortcut creation.', 'It is a config in abyss bucket (https://github.com/abgox/abyss).', 'See https://github.com/abgox/abyss#config for details.')
                }

                # scoop-install config
                'abgox-scoop-install-url-replace-from' = @{
                    symbol  = 'SpaceTab'
                    'zh-CN' = @('需要被替换的 URL 前缀。', '详情参考: https://gitee.com/abgox/scoop-tools')
                    'en-US' = @('The URL prefix to be replaced.', 'See https://github.com/abgox/scoop-tools for details.')
                }
                'abgox-scoop-install-url-replace-to'   = @{
                    symbol  = 'SpaceTab'
                    'zh-CN' = @('需要替换成的 URL 前缀。', '详情参考: https://gitee.com/abgox/scoop-tools')
                    'en-US' = @('The URL prefix to be replaced with.', 'See https://github.com/abgox/scoop-tools for details.')
                }

                # scoop-i18n config
                'abgox-scoop-i18n-language'            = @{
                    symbol  = ''
                    'zh-CN' = @('指定 scoop-i18n 语言。', '详情参考: https://gitee.com/abgox/scoop-i18n')
                    'en-US' = @('Specify the language of scoop-i18n.', 'See https://github.com/abgox/scoop-i18n for details.')
                }
            }

            $configItemList = Get-Member -InputObject $configList -MemberType NoteProperty | ForEach-Object { $_.Name }

            if ($filter_input_arr.Count -eq 1) {
                $configs = Get-Member -InputObject $config -MemberType NoteProperty
                $completions_list = $completions.CompletionText

                $add = @()

                foreach ($c in $configs) {
                    $configName = $c.Name
                    $configValue = $c.Definition -replace '^.+=', ''
                    $configValue = if ($configValue -in @('True', 'False')) { $configValue.ToLower() }else { $configValue }
                    # $info = $PSCompletions.completions_data.scoop.root.config.$($PSCompletions.guid).Where({ $_.CompletionText -eq $configName })[0].ToolTip
                    $info = @($PSCompletions.info.current_value + ': ' + $configValue)
                    if ($configName -notin $completions_list) {
                        if ($configName -in $configItemList) {
                            $configList.$($configName).tip = $info
                        }
                        else {
                            $list += $PSCompletions.return_completion($configName, $PSCompletions.replace_content($info))
                            $add += $configName
                        }
                    }
                }

                $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }

                foreach ($c in $configItemList) {
                    if ($c -notin $add) {
                        $info = if ($configList.$c.tip) { $configList.$c.tip + "`n" + ($configList.$c[$language] -join "`n") } else { $configList.$c[$language] -join "`n" }

                        $list += $PSCompletions.return_completion($c, $PSCompletions.replace_content($info), $configList.$c.symbol)
                    }
                }
            }
            else {
                if ($filter_input_arr[1] -eq 'rm') {
                    $configs = Get-Member -InputObject $config -MemberType NoteProperty
                    foreach ($c in $configs) {
                        $configName = $c.Name
                        $info = @($PSCompletions.info.current_value + ': ' + ($c.Definition -replace '^.+=', ''))
                        $list += $PSCompletions.return_completion($configName, $PSCompletions.replace_content($info))
                    }
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
