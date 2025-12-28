using namespace System.Management.Automation

Set-StrictMode -Off

$_ = Split-Path $PSScriptRoot -Parent
New-Variable -Name PSCompletions -Option Constant -Value @{
    version                 = '6.2.2'
    path                    = @{
        root             = $_
        completions      = Join-Path $_ 'completions'
        core             = Join-Path $_ 'core'
        data             = Join-Path $_ 'data.json'
        temp             = Join-Path $_ 'temp'
        order            = Join-Path $_ 'temp\order'
        completions_json = Join-Path $_ 'temp\completions.json'
        update           = Join-Path $_ 'temp\update.txt'
        change           = Join-Path $_ 'temp\change.txt'
        last_update      = Join-Path $_ 'temp\last-update.txt'
    }
    order                   = [ordered]@{}
    root_cmd                = ''
    completions_data        = @{}
    guid                    = [System.Guid]::NewGuid().Guid
    language                = $PSUICulture
    encoding                = [console]::OutputEncoding
    separator               = [System.IO.Path]::DirectorySeparatorChar
    replace_pattern         = [regex]::new('(?s)\{\{(.*?(\})*)(?=\}\})\}\}', [System.Text.RegularExpressions.RegexOptions]::Compiled)
    input_pattern           = [regex]::new("(?:`"[^`"]*`"|'[^']*'|\S)+", [System.Text.RegularExpressions.RegexOptions]::Compiled)
    menu                    = @{
        const = @{
            symbol_item = @('SpaceTab', 'WriteSpaceTab', 'OptionTab')
            line_item   = @('horizontal', 'vertical', 'top_left', 'bottom_left', 'top_right', 'bottom_right')
            color_item  = @('item_color', 'filter_color', 'border_color', 'status_color', 'tip_color', 'selected_color', 'selected_bgcolor')
            color_value = @('White', 'Black', 'Gray', 'DarkGray', 'Red', 'DarkRed', 'Green', 'DarkGreen', 'Blue', 'DarkBlue', 'Cyan', 'DarkCyan', 'Yellow', 'DarkYellow', 'Magenta', 'DarkMagenta')
            config_item = @(
                'trigger_key', 'between_item_and_symbol', 'status_symbol', 'filter_symbol', 'completion_suffix', 'enable_menu', 'enable_menu_enhance', 'enable_tip', 'enable_hooks_tip', 'enable_tip_when_enhance', 'enable_completions_sort', 'enable_tip_follow_cursor', 'enable_list_follow_cursor', 'enable_path_with_trailing_separator', 'enable_list_loop', 'enable_enter_when_single', 'enable_list_full_width', 'list_min_width', 'list_max_count_when_above', 'list_max_count_when_below', 'height_from_menu_bottom_to_cursor_when_above', 'height_from_menu_top_to_cursor_when_below', 'completions_confirm_limit'
            )
        }
    }
    config                  = @{ function_name = 'PSCompletions' }
    default_config          = [ordered]@{
        # config
        url                                          = ''
        language                                     = $PSUICulture
        enable_auto_alias_setup                      = 1
        enable_completions_update                    = 1
        enable_module_update                         = 1
        enable_cache                                 = 1
        function_name                                = 'PSCompletions'

        # menu symbol
        SpaceTab                                     = '~'
        OptionTab                                    = '?'
        WriteSpaceTab                                = '!'

        # menu line
        horizontal                                   = [string][char]9472 # ─
        vertical                                     = [string][char]9474 # │
        top_left                                     = [string][char]9581 # ╭
        bottom_left                                  = [string][char]9584 # ╰
        top_right                                    = [string][char]9582 # ╮
        bottom_right                                 = [string][char]9583 # ╯

        # menu color
        filter_color                                 = 'Yellow'
        border_color                                 = 'DarkGray'
        item_color                                   = 'Blue'
        status_color                                 = 'Blue'
        tip_color                                    = 'Cyan'

        selected_color                               = 'White'
        selected_bgcolor                             = 'DarkGray'

        # menu config
        trigger_key                                  = 'Tab'
        filter_symbol                                = '[]'
        status_symbol                                = '/'
        between_item_and_symbol                      = ' '
        height_from_menu_bottom_to_cursor_when_above = 0
        height_from_menu_top_to_cursor_when_below    = 0

        enable_menu                                  = 1
        enable_menu_enhance                          = 1
        enable_enter_when_single                     = 0
        enable_list_loop                             = 1
        enable_list_full_width                       = 1
        enable_list_follow_cursor                    = 1

        enable_tip                                   = 1
        enable_hooks_tip                             = 1
        enable_tip_when_enhance                      = 1
        enable_tip_follow_cursor                     = 1

        enable_completions_sort                      = 1
        enable_path_with_trailing_separator          = 1

        list_min_width                               = 10
        list_max_count_when_above                    = 0
        list_max_count_when_below                    = 0

        completion_suffix                            = ' '
        completions_confirm_limit                    = 0
    }
    # 每个补全都默认带有的配置项
    default_completion_item = @('language', 'enable_tip', 'enable_hooks_tip')
    config_item             = @('url', 'language', 'enable_auto_alias_setup', 'enable_completions_update', 'enable_module_update', 'enable_cache', 'function_name')
}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod return_completion {
    param([string]$name, $tip = ' ', [array]$symbols)
    if ($PSCompletions.config.comp_config[$PSCompletions.root_cmd].enable_hooks_tip -eq 0) {
        $tip = ''
    }
    @{
        ListItemText   = $name
        CompletionText = $name
        ToolTip        = $tip
        symbols        = $symbols
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_completion {
    $guid = $PSCompletions.guid
    function getCompletions {
        $obj = @{}

        # XXX: 这里必须是引用类型
        $special_options = @{
            WriteSpaceTab              = @()
            WriteSpaceTab_and_SpaceTab = @()
        }
        function parseJson($cmds, $obj, [string]$cmdO, [switch]$isOption) {
            if ($null -eq $obj[$cmdO].$guid) {
                $obj[$cmdO] = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
                $obj[$cmdO].$guid = @()
            }
            foreach ($cmd in $cmds) {
                $name = $cmd.name
                $next = $cmd.next
                $options = $cmd.options

                $symbols = @()
                if ($isOption) {
                    if ($null -eq $next -and $null -eq $options) {
                        $symbols += 'OptionTab'
                    }
                    else {
                        $symbols += 'WriteSpaceTab'
                        if ($next -is [array] -or $options -is [array]) {
                            $symbols += 'SpaceTab'
                        }
                    }
                }
                else {
                    if ($next -is [array] -or $options -is [array]) {
                        $symbols += 'SpaceTab'
                    }
                }

                $tip = $cmd.tip
                $alias = $cmd.alias

                $alias_list = $alias + $name

                # hide 值为 true 的补全将被过滤掉，用于配合 hooks.ps1 中添加动态补全
                # 如果不过滤掉，会和 hooks.ps1 中添加的动态补全产生重复
                if (!$cmd.hide) {
                    $obj[$cmdO].$guid += @{
                        CompletionText = $name
                        ListItemText   = $name
                        ToolTip        = $tip
                        symbols        = $symbols
                        alias          = $alias_list
                    }

                    foreach ($a in $alias) {
                        $obj[$cmdO].$guid += @{
                            CompletionText = $a
                            ListItemText   = $a
                            ToolTip        = $tip
                            symbols        = $symbols
                            alias          = $alias_list
                        }
                    }
                }

                if ($symbols) {
                    if ('WriteSpaceTab' -in $symbols) {
                        $pad = if ($cmdO -in @('rootOptions', 'commonOptions')) { ' ' }else { $cmdO + ' ' }
                        $special_options.WriteSpaceTab += $pad + $name
                        foreach ($a in $alias) { $special_options.WriteSpaceTab += $pad + $a }
                        if ('SpaceTab' -in $symbols) {
                            $special_options.WriteSpaceTab_and_SpaceTab += $pad + $name
                            foreach ($a in $alias) { $special_options.WriteSpaceTab_and_SpaceTab += $pad + $a }
                        }
                    }
                }
                if ($options) {
                    parseJson $options $obj[$cmdO] $name -isOption
                    foreach ($a in $alias) {
                        parseJson $options $obj[$cmdO] $a -isOption
                    }
                }
                if ($next -or 'WriteSpaceTab' -in $symbols) {
                    parseJson $next $obj[$cmdO] $name
                    foreach ($a in $alias) {
                        parseJson $next $obj[$cmdO] $a
                    }
                }
            }
        }
        if ($PSCompletions.completions[$root].root) {
            parseJson $PSCompletions.completions[$root].root $obj 'root'
        }
        if ($PSCompletions.completions[$root].options) {
            parseJson $PSCompletions.completions[$root].options $obj 'rootOptions' -isOption
        }
        if ($PSCompletions.completions[$root].common_options) {
            parseJson $PSCompletions.completions[$root].common_options $obj 'commonOptions' -isOption
        }
        $PSCompletions.completions_data."$($root)_WriteSpaceTab" = [System.Linq.Enumerable]::Distinct([string[]]$special_options.WriteSpaceTab)
        $PSCompletions.completions_data."$($root)_WriteSpaceTab_and_SpaceTab" = [System.Linq.Enumerable]::Distinct([string[]]$special_options.WriteSpaceTab_and_SpaceTab)
        return $obj
    }
    function handleCompletions {
        param($completions)
        return $completions
    }
    function filterCompletions {
        function readObject {
            param (
                [hashtable]$obj, # 要读取的对象
                [string[]]$attrs, # 属性名称数组
                $return = $null # 如果属性不存在，返回的默认值
            )
            $v = $obj
            foreach ($attr in $attrs) {
                if ($v -is [hashtable] -and $v.ContainsKey($attr)) {
                    $v = $v[$attr]
                }
                else {
                    return $return
                }
            }
            return $v
        }
        function filterInput {
            param(
                [array]$input_arr
            )
            $need_skip = $false
            $filter_input_arr = @()
            $last_item = $input_arr[-1]
            $pre_cmd = ''

            $commonOptions = @($PSCompletions.completions_data."$($root)_common_options")
            $WriteSpaceTab = $PSCompletions.completions_data."$($root)_WriteSpaceTab"
            $WriteSpaceTab_and_SpaceTab = $PSCompletions.completions_data."$($root)_WriteSpaceTab_and_SpaceTab"

            foreach ($_ in $input_arr) {
                if ($need_skip) {
                    if ($_ -like '-*') {
                        if ($_ -ceq $last_item) {
                            $filter_input_arr += $_
                        }
                    }
                    else {
                        $need_skip = $false
                        continue
                    }
                }
                else {
                    $pad = if ($_ -cin $commonOptions) { '' } else { $pre_cmd }
                    if ($_ -like '-*') {
                        if ("$pad $_" -cin $WriteSpaceTab) {
                            if ("$pad $_" -cin $WriteSpaceTab_and_SpaceTab) {
                                # 如果选项是最后一个
                                if ($_ -ceq $last_item) {
                                    $filter_input_arr += $_
                                }
                                else {
                                    $need_skip = $true
                                }
                            }
                            else {
                                # 需要用户输入，但是没有候选项
                                $need_skip = $true
                            }
                        }
                    }
                    else {
                        $filter_input_arr += $_
                        # 记录上一个子命令
                        $pre_cmd = $_
                    }
                }
            }
            return $filter_input_arr
        }

        $filter_list = @()
        $PSCompletions.filter_input_arr = @()
        $PSCompletions.filter_input_str = ''

        # 如果不只是输入了根命令
        if ($input_arr) {
            # 这里过滤后只存在两种情况
            # 1. 没有选项
            # 2. 最后一个是选项

            if ($space_tab -or $PSCompletions.input_arr[-1] -like '-*=') {
                $filter_input_arr = [array](filterInput $input_arr)
            }
            else {
                $handle_input_arr = if ($input_arr.Count -eq 1) { , @() }else { $input_arr[0..($input_arr.Count - 2)] }
                $filter_input_arr = [array](filterInput $handle_input_arr)
            }

            if ($filter_input_arr.Count) {
                $PSCompletions.filter_input_arr = $filter_input_arr
            }
            else {
                $c = $completions.root.$guid
                if ($c) {
                    $filter_list += $c
                }
                $c = $completions.rootOptions.$guid
                if ($c) {
                    $filter_list += $c
                }
                $c = $completions.commonOptions.$guid
                if ($c) {
                    $filter_list += $c
                }
                return $filter_list
            }

            $PSCompletions.filter_input_str = $filter_input_str = $filter_input_arr -join ' '
            $last_item = $filter_input_arr[-1]

            $no_options = $true
            $all_options = $true

            foreach ($c in $filter_input_arr) {
                if ($c -like "-*") {
                    $no_options = $false
                }
                else {
                    $all_options = $false
                }
            }

            if ($last_item -like '-*') {
                if ($all_options) {
                    # 如果全是选项，只可能是根选项或通用选项
                    $data = $PSCompletions.completions_data[$root].commonOptions.$last_item.$guid
                    if (!$data.Count) {
                        $data = $PSCompletions.completions_data[$root].rootOptions.$last_item.$guid
                    }
                    if ($data.Count) {
                        $filter_list = $data
                    }
                    else {
                        $data = readObject $completions.root ($filter_input_arr + $guid) (, @())
                        if ($data.Count) {
                            $filter_list += $data
                        }
                        else {
                            $c = $completions.root.$guid
                            if ($c) {
                                $filter_list += $c
                            }
                            $c = $completions.rootOptions.$guid
                            if ($c) {
                                $filter_list += $c
                            }
                            $c = $completions.commonOptions.$guid
                            if ($c) {
                                $filter_list += $c
                            }
                        }
                    }
                }
                else {
                    if ($last_item -cin $PSCompletions.completions_data."$($root)_common_options") {
                        $filter_list = $PSCompletions.completions_data[$root].commonOptions.$last_item.$guid
                    }
                    else {
                        $filter_list = readObject $completions.root ($filter_input_arr + $guid) (, @())
                    }
                }
            }
            else {
                $filter_list += readObject $completions.root ($filter_input_arr + $guid) (, @())
                if ($completions.commonOptions.$guid) {
                    $filter_list += $completions.commonOptions.$guid
                }
            }
            return $filter_list
        }
        else {
            # 如果 $input_arr 没有值，即只输入了根命令进行补全
            if ($completions.root.$guid) {
                $filter_list += $completions.root.$guid
            }
            if ($completions.rootOptions.$guid) {
                $filter_list += $completions.rootOptions.$guid
            }
            if ($completions.commonOptions.$guid) {
                $filter_list += $completions.commonOptions.$guid
            }
            return $filter_list
        }
    }

    if ($PSCompletions.job.State -eq 'Completed') {
        if (!$PSCompletions._has_add_completion) {
            $_data = Receive-Job $PSCompletions.job
            $PSCompletions.completions = $_data.completions
            $PSCompletions.completions_data = $_data.completions_data
        }
        Remove-Job $PSCompletions.job
        $PSCompletions.job = $null
    }
    if (!$PSCompletions.config.enable_cache) {
        $PSCompletions.completions[$root] = $null
        $PSCompletions.completions_data[$root] = $null
    }

    if (!$PSCompletions.completions[$root]) {
        $language = $PSCompletions.get_language($root)
        $PSCompletions.completions[$root] = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$root/language/$language.json"))
    }

    $input_arr = @($input_arr)
    $PSCompletions.input_arr = $input_arr

    # 使用 hooks 覆盖默认的函数，实现一些特殊的需求，比如一些补全的动态加载
    if ($PSCompletions.config.comp_config[$root].enable_hooks) {
        . "$($PSCompletions.path.completions)/$root/hooks.ps1"
    }
    if (!$PSCompletions.completions_data[$root]) {
        $PSCompletions.completions_data[$root] = getCompletions
        $PSCompletions.completions_data."$($root)_common_options" = $PSCompletions.completions_data[$root].commonOptions.$guid.CompletionText
    }
    $completions = $PSCompletions.completions_data[$root]
    $filter_list = handleCompletions ([array](filterCompletions))

    if ($filter_list.Count -gt 1) {
        $_filter_list = foreach ($_ in $filter_list) { if ($null -ne $_.ListItemText) { $_ } }
    }
    else {
        $_filter_list = $filter_list.Where({ $null -ne $_.ListItemText })
    }

    $filter_list = [System.Collections.Generic.List[object]]@()
    if ($space_tab -or $PSCompletions.input_arr[-1] -like '-*=') {
        foreach ($item in $_filter_list) {
            if ($item.CompletionText -notlike "-*" -or $item.CompletionText -cnotin $input_arr) {
                $isContinue = $false
                if ($item.alias) {
                    foreach ($a in $item.alias) {
                        if ($a -cin $input_arr) {
                            $isContinue = $true
                            break
                        }
                    }
                }
                if ($isContinue) {
                    continue
                }
                $padSymbols = foreach ($c in $item.symbols) { $PSCompletions.config.$c }
                $padSymbols = if ($padSymbols) { "$($PSCompletions.config.between_item_and_symbol)$($padSymbols -join '')" }else { '' }
                $filter_list.Add(@{
                        ListItemText   = $item.ListItemText
                        padSymbols     = $padSymbols
                        CompletionText = $item.CompletionText
                        ToolTip        = $item.ToolTip
                    })
            }
        }
    }
    else {
        $_input_arr = [System.Collections.Generic.List[string]]$PSCompletions.input_arr.Clone()
        $_input_arr.RemoveAt(($_input_arr.Count - 1))
        foreach ($item in $_filter_list) {
            if ($item.CompletionText -like "$([WildcardPattern]::Escape($input_arr[-1]))*") {
                $isContinue = $false
                foreach ($a in $item.alias) {
                    if ($a -cin $_input_arr) {
                        $isContinue = $true
                        break
                    }
                }
                if ($isContinue) {
                    continue
                }
                $padSymbols = foreach ($c in $item.symbols) { $PSCompletions.config.$c }
                $padSymbols = if ($padSymbols) { "$($PSCompletions.config.between_item_and_symbol)$($padSymbols -join '')" }else { '' }
                $filter_list.Add(@{
                        ListItemText   = $item.ListItemText
                        padSymbols     = $padSymbols
                        CompletionText = $item.CompletionText
                        ToolTip        = $item.ToolTip
                    })
            }
        }
    }
    if ($root -eq 'PSCompletions') {
        $cmds = Get-Command
        $has_command = foreach ($c in $cmds) { if ($c.Name -eq $root) { $c; break } }
    }
    else {
        $has_command = Get-Command [regex]::Escape($root) -ErrorAction SilentlyContinue
    }
    if ($PSCompletions.config.enable_completions_sort -and $has_command) {
        $path_order = "$($PSCompletions.path.order)/$root.json"
        if ($PSCompletions.order."$($root)_job") {
            if ($PSCompletions.order."$($root)_job".State -eq 'Completed') {
                $PSCompletions.order[$root] = Receive-Job $PSCompletions.order."$($root)_job"
                Remove-Job $PSCompletions.order."$($root)_job"
                $PSCompletions.order.Remove("$($root)_job")
            }
        }
        else {
            if (Test-Path $path_order) {
                try {
                    $PSCompletions.order[$root] = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($path_order))
                }
                catch {
                    $PSCompletions.order[$root] = $null
                }
            }
            else {
                $PSCompletions.order[$root] = $null
            }
        }
        $order = $PSCompletions.order[$root]
        if ($order) {
            $PSCompletions._i = 0 # 这里使用 $PSCompletions._i 而非 $i 是因为在 Sort-Object 中，普通的 $i 无法累计
            $filter_list = $filter_list | Sort-Object {
                $PSCompletions._i --
                # 不能使用 $order.($_.CompletionText)，它可能获取到对象中的 OverloadDefinitions
                $o = $order[$_.CompletionText]
                if ($o) { $o }else { $PSCompletions._i }
            } -Descending -CaseSensitive
        }
        $PSCompletions.order_job((Get-PSReadLineOption).HistorySavePath, $root, $path_order)
    }
    return $filter_list
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_data_by_runspace {
    param(
        [array]$list, # 需要处理的数据
        # 处理逻辑，可以获取三个参数
        # 1. $arr: 分组后的部分需要处理的数据
        # 2. $PSCompletions
        # 3. $Host.UI
        [scriptblock]$handler,
        # 处理结果，可以获取一个参数
        # 1. $results: $handler 脚本块返回的结果
        [scriptblock]$handleResult
    )
    $runspaces = @()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
    $runspacePool.Open()

    $arrs = $PSCompletions.split_array($list, [Environment]::ProcessorCount, $true)
    foreach ($arr in $arrs) {
        $runspace = [powershell]::Create().AddScript($handler).AddArgument($arr).AddArgument($PSCompletions).AddArgument($Host.UI)
        $runspace.RunspacePool = $runspacePool
        $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
    }
    $return = @()
    foreach ($rs in $runspaces) {
        $results = $rs.Runspace.EndInvoke($rs.Job)
        $rs.Runspace.Dispose()
        $return += & $handleResult $results
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
    return $return
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod split_array {
    <#
    .Synopsis
        分割数组
    .Description
        三个参数:
        $array: 数组
        $count: 每个数组中的元素个数
        $by_count: 如果此值为 $true, 则 $count 为分割的数组个数，否则为每个数组中的元素个数
    #>
    param ([array]$array, [int]$count, [bool]$by_count)
    if ($by_count) {
        $ChunkSize = [math]::Ceiling($array.Length / $count)
    }
    else {
        $ChunkSize = $count
    }
    $chunks = for ($i = 0; $i -lt $array.Length; $i += $ChunkSize) {
        , ($array[$i..([math]::Min($i + $ChunkSize - 1, $array.Length - 1))])
    }
    $chunks
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_dir {
    param([string]$path)
    if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_language {
    param ([string]$completion)
    $path_config = "$($PSCompletions.path.completions)/$completion/config.json"

    $content_config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
    if (!$content_config.language) {
        $PSCompletions.download_file("completions/$completion/config.json", $path_config, $PSCompletions.urls)
        $content_config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
        $content_config | ConvertTo-Json -Compress | Out-File $path_config -Encoding utf8 -Force
    }
    $lang = $PSCompletions.config.comp_config[$completion].language
    if ($lang) {
        $config_language = $lang
    }
    else {
        $config_language = $null
    }
    if ($config_language) {
        $language = if ($config_language -in $content_config.language) { $config_language }else { $content_config.language[0] }
    }
    else {
        $language = if ($PSCompletions.language -in $content_config.language) { $PSCompletions.language }else { $content_config.language[0] }
    }
    $language
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_content {
    param ([string]$path)
    $res = (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue).Where({ $_ -ne '' })
    if ($res) { return $res }
    , @()
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_raw_content {
    param ([string]$path, [bool]$trim = $true)
    $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    if ($res) {
        if ($trim) { return $res.Trim() }
        return $res
    }
    ''
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod replace_content {
    param ($data, $separator = '')
    $data = $data -join $separator
    if ($data -notlike '*{{*') { return $data }
    $matches = [regex]::Matches($data, $PSCompletions.replace_pattern)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
    }
    if ($data -match $PSCompletions.replace_pattern) { $PSCompletions.replace_content($data) }else { return $data }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod write_with_color {
    param([string]$str)

    Set-Alias Write-Host Microsoft.PowerShell.Utility\Write-Host -ErrorAction SilentlyContinue

    $color_list = @()
    $str = $str -replace "`n", $PSCompletions.guid
    $str_list = foreach ($_ in ($str -split '(<\@[^>]+>.*?(?=<\@|$))').Where({ $_ -ne '' })) {
        if ($_ -match '<\@([\s\w]+)>(.*)') {
            ($matches[2] -replace $PSCompletions.guid, "`n") -replace '^<\@>', ''
            $color = $matches[1] -split ' '
            $color_list += @{
                color   = $color[0]
                bgColor = $color[1]
            }
        }
        else {
            ($_ -replace $PSCompletions.guid, "`n") -replace '^<\@>', ''
            $color_list += @{}
        }
    }
    $str_list = @($str_list)
    for ($i = 0; $i -lt $str_list.Count; $i++) {
        $color = $color_list[$i].color
        $bgColor = $color_list[$i].bgColor
        if ($color) {
            if ($bgColor) {
                Write-Host $str_list[$i] -ForegroundColor $color -BackgroundColor $bgColor -NoNewline
            }
            else {
                Write-Host $str_list[$i] -ForegroundColor $color -NoNewline
            }
        }
        else {
            Write-Host $str_list[$i] -NoNewline
        }
    }
    Write-Host ''
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod show_with_less {
    param (
        $str_list,
        [string]$color = 'Green',
        [int]$show_line = [System.Console]::WindowHeight - 7
    )

    Set-Alias Write-Host Microsoft.PowerShell.Utility\Write-Host -ErrorAction SilentlyContinue

    if ($str_list -is [string]) {
        $str_list = $str_list -split "`n"
    }
    $i = 0
    $need_less = [System.Console]::WindowHeight -lt ($str_list.Count + 2)
    if ($need_less) {
        $lines = $str_list.Count - $show_line
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.less_tip))
        while ($i -lt $str_list.Count -and $i -lt $show_line) {
            Write-Host $str_list[$i] -ForegroundColor $color
            $i++
        }
        while ($i -lt $str_list.Count) {
            $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
            if ($keyCode -ne 13) {
                break
            }
            Write-Host $str_list[$i] -ForegroundColor $color
            $i++
        }
        $end = if ($i -lt $str_list.Count) { $false }else { $true }
        if ($end) {
            Write-Host ' '
            Write-Host '(End)' -ForegroundColor Black -BackgroundColor White -NoNewline
            while ($end) {
                $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
                if ($keyCode -ne 13) {
                    Write-Host ' '
                    break
                }
            }
        }
    }
    else {
        foreach ($_ in $str_list) { Write-Host $_ -ForegroundColor $color }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod show_with_less_table {
    param (
        [array]$str_list,
        [array]$header = @('key', 'value', 5),
        [scriptblock]$do = {},
        [int]$show_line = [System.Console]::WindowHeight - 7
    )

    Set-Alias Write-Host Microsoft.PowerShell.Utility\Write-Host -ErrorAction SilentlyContinue

    $str_list = @(
        @{
            content = "`n{0,-$($header[2] + 3)} {1}" -f $header[0], $header[1]
            color   = 'Cyan'
        },
        @{
            content = "{0,-$($header[2] + 3)} {1}" -f ('-' * $header[0].Length), ('-' * $header[1].Length)
            color   = 'Cyan'
        }
    ) + $str_list
    $i = 0
    $need_less = [System.Console]::WindowHeight -lt ($str_list.Count + 2)
    if ($need_less) {
        $lines = $str_list.Count - $show_line
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.less_tip))
        & $do
        while ($i -lt $str_list.Count -and $i -lt $show_line) {
            if ($str_list[$i].bgColor) {
                Write-Host $str_list[$i].content -ForegroundColor $str_list[$i].color -BackgroundColor $str_list[$i].bgColor
            }
            else {
                Write-Host $str_list[$i].content -ForegroundColor $str_list[$i].color
            }
            $i++
        }
        while ($i -lt $str_list.Count) {
            $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
            if ($keyCode -ne 13) {
                break
            }
            if ($str_list[$i].bgColor) {
                Write-Host $str_list[$i].content -ForegroundColor $str_list[$i].color -BackgroundColor $str_list[$i].bgColor
            }
            else { Write-Host $str_list[$i].content -ForegroundColor $str_list[$i].color }
            $i++
        }
        $end = if ($i -lt $str_list.Count) { $false }else { $true }
        if ($end) {
            Write-Host ' '
            Write-Host '(End)' -ForegroundColor Black -BackgroundColor White -NoNewline
            while ($end) {
                $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
                if ($keyCode -ne 13) {
                    Write-Host ' '
                    break
                }
            }
        }
    }
    else {
        & $do
        foreach ($_ in $str_list) {
            if ($_.bgColor) {
                Write-Host $_.content -ForegroundColor $_.color -BackgroundColor $_.bgColor[2]
            }
            else {
                Write-Host $_.content -ForegroundColor $_.color
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_list {
    $PSCompletions.ensure_dir($PSCompletions.path.temp)
    if (!(Test-Path $PSCompletions.path.completions_json)) {
        @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
    }
    $current_list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list
    $isErr = $true

    $params = @{
        ErrorAction = 'Stop'
    }
    if ($PSEdition -eq 'Core') {
        $params['OperationTimeoutSeconds'] = 30
    }
    else {
        $params['TimeoutSec'] = 30
    }

    foreach ($url in $PSCompletions.urls) {
        $params['Uri'] = "$url/completions.json"
        try {
            $response = Invoke-RestMethod @params
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            continue
        }

        $remote_list = $response.list

        $diff = Compare-Object $remote_list $current_list -PassThru
        if ($diff) {
            try {
                $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8 -ErrorAction Stop
                $response | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force -ErrorAction Stop
                $PSCompletions.list = $remote_list
            }
            catch {
                Write-Host $_.Exception.Message -ForegroundColor Red
                return $false
            }
        }
        else {
            Clear-Content $PSCompletions.path.change -Force
            $PSCompletions.list = $current_list
        }
        $isErr = $false
        return $remote_list
    }
    if ($isErr) {
        return $false
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_file {
    param(
        [string]$path, # 相对于 $baseUrl 的文件路径
        [string]$file,
        [array]$baseUrl
    )

    $params = @{
        ErrorAction = 'Stop'
    }
    if ($PSEdition -eq 'Core') {
        $params['OperationTimeoutSeconds'] = 30
    }
    else {
        $params['TimeoutSec'] = 30
    }

    for ($i = 0; $i -lt $baseUrl.Count; $i++) {
        $item = $baseUrl[$i]
        $url = $item + '/' + $path
        $params['Uri'] = $url
        $params['OutFile'] = $file
        try {
            Invoke-RestMethod @params
            break
        }
        catch {
            if ($i -eq $baseUrl.Count - 1) {
                throw
            }
            else {
                Write-Host $_.Exception.Message -ForegroundColor Red
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod add_completion {
    param (
        [string]$completion,
        [bool]$log = $true
    )

    $PSCompletions._has_add_completion = $log -and $true

    $PSCompletions.completions_data[$completion] = $null
    $PSCompletions.completions[$completion] = $null

    $url = "completions/$completion"

    $is_update = Test-Path "$($PSCompletions.path.completions)/$completion"

    $completion_dir = Join-Path $PSCompletions.path.completions $completion
    $language_dir = Join-Path $completion_dir 'language'

    $PSCompletions.ensure_dir($PSCompletions.path.completions)
    $PSCompletions.ensure_dir($completion_dir)
    $PSCompletions.ensure_dir($language_dir)

    $download_info = @{
        url  = "$url/config.json"
        file = Join-Path $completion_dir 'config.json'
    }
    $PSCompletions.download_file($download_info.url, $download_info.file, $PSCompletions.urls)

    $config = $PSCompletions.get_raw_content("$completion_dir/config.json") | ConvertFrom-Json
    $config | ConvertTo-Json -Compress | Out-File $download_info.file -Encoding utf8 -Force

    $files = @(
        @{
            Uri     = "$url/guid.json"
            OutFile = Join-Path $completion_dir 'guid.json'
        }
    )
    foreach ($_ in $config.language) {
        $files += @{
            Uri     = "$url/language/$_.json"
            OutFile = Join-Path $language_dir "$_.json"
        }
    }
    if ($null -ne $config.hooks) {
        $files += @{
            Uri     = "$url/hooks.ps1"
            OutFile = Join-Path $completion_dir 'hooks.ps1'
        }
    }

    foreach ($file in $files) {
        $download_info = @{
            url  = $file.Uri
            file = $file.OutFile
        }
        try {
            $PSCompletions.download_file($download_info.url, $download_info.file, $PSCompletions.urls)
            if ($download_info.file -match '\.json$') {
                $PSCompletions.get_raw_content($download_info.file) | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 100 | Out-File $download_info.file -Encoding utf8 -Force
            }
        }
        catch {
            Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue
            throw $_
        }
    }

    # 显示下载信息
    $download = if ($is_update) { $PSCompletions.info.update.doing }else { $PSCompletions.info.add.doing }
    if ($log) { $PSCompletions.write_with_color("`n" + $PSCompletions.replace_content($download)) }

    $done = if ($is_update) { $PSCompletions.info.update.done }else { $PSCompletions.info.add.done }

    if ($completion -notin $PSCompletions.data.list) {
        $PSCompletions.data.list += $completion
        $PSCompletions._need_update_data = $true
    }
    if (!$PSCompletions.data.alias[$completion]) {
        $PSCompletions.data.alias[$completion] = @()
    }

    $PSCompletions._alias_conflict = $false
    $conflict_alias_list = @()
    if ($config.alias) {
        foreach ($a in $config.alias) {
            if ($a -notin $PSCompletions.data.alias[$completion]) {
                $PSCompletions.data.alias[$completion] += $a
                if ($PSCompletions.data.aliasMap[$a]) {
                    $PSCompletions._alias_conflict = $true
                    $conflict_alias_list += $a
                }
                else {
                    $PSCompletions.data.aliasMap.$a = $completion
                }
                $PSCompletions._need_update_data = $true
            }
        }
    }
    else {
        if ($completion -notin $PSCompletions.data.alias[$completion]) {
            $PSCompletions.data.alias[$completion] += $completion
            if ($PSCompletions.data.aliasMap[$completion]) {
                $PSCompletions._alias_conflict = $true
                $conflict_alias_list += $completion
            }
            else {
                $PSCompletions.data.aliasMap[$completion] = $completion
            }
            $PSCompletions._need_update_data = $true
        }
    }

    if ($config.alias) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.add.show_alias))
    }
    if ($PSCompletions._alias_conflict) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.err.alias_conflict))
    }

    $language = $PSCompletions.get_language($completion)
    $json = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$completion_dir/language/$language.json"))
    if (!$PSCompletions.completions) {
        $PSCompletions.completions = @{}
    }
    $PSCompletions.completions[$completion] = $json

    if ($log) { $PSCompletions.write_with_color($PSCompletions.replace_content($done)) }

    if ($json.config) {
        if (!$PSCompletions.config.comp_config[$completion]) {
            $PSCompletions.config.comp_config[$completion] = @{}
        }
        foreach ($_ in $json.config) {
            if (!$PSCompletions.config.comp_config[$completion].$($_.name)) {
                $PSCompletions.config.comp_config[$completion].$($_.name) = $_.value
                $PSCompletions._need_update_data = $true
            }
        }
    }
    if ($null -ne $config.hooks) {
        if (!$PSCompletions.config.comp_config[$completion]) {
            $PSCompletions.config.comp_config[$completion] = @{}
        }
        if ($null -eq $PSCompletions.config.comp_config[$completion].enable_hooks) {
            $PSCompletions.config.comp_config[$completion].enable_hooks = [int]$config.hooks
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod new_data {
    $data = @{
        list     = @()
        alias    = @{}
        aliasMap = @{}
        config   = $PSCompletions.default_config
    }
    $data.config.comp_config = @{}
    $items = Get-ChildItem -Path $PSCompletions.path.completions
    foreach ($_ in $items) {
        $name = $_.Name
        $data.list += $name
        $data.alias.$name = @()
        $path_config = Join-Path $_.FullName 'config.json'
        if (!(Test-Path $path_config)) {
            continue
        }
        $config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
        if ($config.alias) {
            foreach ($a in $config.alias) {
                $data.alias.$name += $a
                $data.aliasMap.$a = $name
            }
        }
        else {
            $data.alias.$name += $name
            $data.aliasMap.$name = $name
        }
        $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }
        $json = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$($_.FullName)/language/$language.json"))
        $data.config.comp_config.$name = @{}
        foreach ($_ in $json.config) {
            $data.config.comp_config.$name.$($_.name) = $_.value
        }
        if ($null -ne $config.hooks) {
            $data.config.comp_config.$name.enable_hooks = [int]$config.hooks
        }
    }
    $data | ConvertTo-Json -Depth 5 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
    $PSCompletions.data = $data
    $null = $PSCompletions.download_list()
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod init_data {
    $PSCompletions.completions = @{}
    if ((Test-Path $PSCompletions.path.data) -and !$PSCompletions.is_first_init) {
        $PSCompletions.data = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($PSCompletions.path.data))
    }
    else {
        $PSCompletions.new_data()
    }
    $PSCompletions.config = $PSCompletions.data.config
    $PSCompletions.language = $PSCompletions.config.language

    if ($PSCompletions.config.url) {
        $PSCompletions.url = $PSCompletions.config.url
        $PSCompletions.urls = @($PSCompletions.config.url)
    }
    else {
        if ($PSCompletions.language -eq 'zh-CN') {
            $PSCompletions.url = 'https://gitee.com/abgox/PSCompletions/raw/main'
            $PSCompletions.urls = @('https://gitee.com/abgox/PSCompletions/raw/main', 'https://github.com/abgox/PSCompletions/raw/main', 'https://abgox.github.io/PSCompletions' )
        }
        else {
            $PSCompletions.url = 'https://github.com/abgox/PSCompletions/raw/main'
            $PSCompletions.urls = @('https://github.com/abgox/PSCompletions/raw/main', 'https://gitee.com/abgox/PSCompletions/raw/main', 'https://abgox.github.io/PSCompletions')
        }
    }

    $PSCompletions.list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list

    $PSCompletions.update = $PSCompletions.get_content($PSCompletions.path.update)
    if ('psc' -notin $PSCompletions.data.list) {
        $PSCompletions.add_completion('psc', $false)
        $PSCompletions.data | ConvertTo-Json -Depth 5 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
        $PSCompletions.info = $PSCompletions.completions.psc.info
    }
    else {
        $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }
        $PSCompletions.info = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/psc/language/$language.json")).info
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_powershell_menu {
    param([array]$filter_list)
    if ($Host.UI.RawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        return ''
    }

    $json = $PSCompletions.completions.$($PSCompletions.root_cmd)
    $info = $json.info

    $suffix = $PSCompletions.config.completion_suffix

    # is_show_tip
    $enable_tip = $PSCompletions.config.comp_config.$($PSCompletions.root_cmd).enable_tip
    if ($null -ne $enable_tip) {
        $PSCompletions.menu.is_show_tip = $enable_tip
    }
    else {
        $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip
    }

    if ($PSCompletions.menu.is_show_tip) {
        foreach ($_ in $filter_list) {
            if ($null -ne $_.ToolTip) {
                $tip = $PSCompletions.replace_content($_.ToolTip -join "`n")
            }
            else {
                $tip = ' '
            }
            if ($PSCompletions.input_arr[-1] -like "-*=") {
                [System.Management.Automation.CompletionResult]::new("$($PSCompletions.input_arr[-1])$($_.CompletionText)$suffix", ($_.ListItemText + $_.padSymbols), [System.Management.Automation.CompletionResultType]::ParameterValue, $tip)
            }
            else {
                [System.Management.Automation.CompletionResult]::new("$($_.CompletionText)$suffix", ($_.ListItemText + $_.padSymbols), [System.Management.Automation.CompletionResultType]::ParameterValue, $tip)
            }
        }
    }
    else {
        foreach ($_ in $filter_list) {
            if ($PSCompletions.input_arr[-1] -like "-*=") {
                [System.Management.Automation.CompletionResult]::new("$($PSCompletions.input_arr[-1])$($_.CompletionText)$suffix", ($_.ListItemText + $_.padSymbols), [System.Management.Automation.CompletionResultType]::ParameterValue, ' ')
            }
            else {
                [System.Management.Automation.CompletionResult]::new("$($_.CompletionText)$suffix", ($_.ListItemText + $_.padSymbols), [System.Management.Automation.CompletionResultType]::ParameterValue, ' ')
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod argc_completions {
    param(
        [array]$completions # The list of completions.
    )
    foreach ($c in $completions) {
        $aliasList = @($c)
        $alias = Get-Alias -Definition $c -ErrorAction SilentlyContinue
        if ($alias) {
            $aliasList += $alias.Name
        }
        foreach ($a in $aliasList) {
            Register-ArgumentCompleter -Native -CommandName $a -ScriptBlock {
                param($wordToComplete, $commandAst, $cursorPosition)
                $words = @(
                    foreach ($_ in $commandAst.CommandElements.Where({ $_.Extent.StartOffset -lt $cursorPosition })) {
                        $word = $_.ToString()
                        if ($word.Length -gt 2) {
                            if (($word.StartsWith('"') -and $word.EndsWith('"')) -or ($word.StartsWith("'") -and $word.EndsWith("'"))) {
                                $word = $word.Substring(1, $word.Length - 2)
                            }
                        }
                        $word
                    }
                )

                $alias = Get-Alias -Name $words[0] -ErrorAction SilentlyContinue
                if ($alias) {
                    $words[0] = $alias.Definition
                }

                $emptyS = ''
                if ($PSVersionTable.PSVersion.Major -eq 5) {
                    $emptyS = '""'
                }
                $lastElemIndex = -1
                if ($words.Count -lt $commandAst.CommandElements.Count) {
                    $lastElemIndex = $words.Count - 1
                }
                if ($commandAst.CommandElements[$lastElemIndex].Extent.EndOffset -lt $cursorPosition) {
                    $words += $emptyS
                }

                foreach ($_ in @((argc --argc-compgen powershell $emptyS $words) -split "`n")) {
                    $parts = ($_ -split "`t")
                    if ($PSCompletions.config.enable_tip_when_enhance) {
                        $tip = if ($parts[3] -eq '') { ' ' }else { $parts[3] }
                        [System.Management.Automation.CompletionResult]::new($parts[0], $parts[0], [System.Management.Automation.CompletionResultType]::ParameterValue, $tip)
                    }
                    else {
                        [System.Management.Automation.CompletionResult]::new($parts[0], $parts[0], [System.Management.Automation.CompletionResultType]::ParameterValue, ' ')
                    }
                }
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod wrap_whitespace {
    param(
        [string]$String
    )
    if ([string]::IsNullOrWhiteSpace($String)) {
        return "`"$String`""
    }
    if ($String.StartsWith(' ') -or $String.EndsWith(' ')) {
        if ($String.Contains('"')) {
            if ($String.Contains("'")) {
                return $String
            }
            else {
                return "'$String'"
            }
        }
        else {
            return "`"$String`""
        }
    }
    return $String
}

if ($IsWindows -or $PSEdition -eq 'Desktop') {
    try {
        if ($PSCompletions.path.root -like "$env:ProgramFiles*" -or $PSCompletions.path.root -like "$env:SystemRoot*") {
            if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Microsoft.PowerShell.Utility\Write-Host -ForegroundColor Red @"

[PSCompletions] Administrator Rights Required
-------------------------------------------------
PSCompletions is installed in a system-level directory.
Location: $($PSCompletions.path.root)

To use PSCompletions normally, please:
1. Run PowerShell as Administrator.
2. Or reinstall the module to a user-writable location via '-Scope CurrentUser'.

Refer to: https://pscompletions.abgox.com/faq/require-admin

"@
                return
            }
        }
    }
    catch {}

    # Windows...
    . $PSScriptRoot\completion\win.ps1

    # menu
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod parse_menu_list {
        # X
        if ($menu.need_full_width -or !$config.enable_list_follow_cursor) {
            $menu.pos.X = 0
        }
        else {
            $menu.pos.X = $rawUI.CursorPosition.X
            # 如果跟随鼠标，且超过右侧边界，则向左偏移
            $edge = $rawUI.BufferSize.Width - 1 - $menu.ui_width
            if ($edge -lt $menu.pos.X) {
                $menu.pos.X = $edge
            }
        }

        # Y
        $menu.ui_height = $menu.filter_list.Count + 2
        if ($menu.is_show_above) {
            if ($menu.cursor_to_top -lt $menu.ui_height) {
                $menu.ui_height = $menu.cursor_to_top
            }
            $list_limit = if ($config.list_max_count_when_above -gt 0) { $config.list_max_count_when_above + 2 }else { 12 }
            if ($list_limit -lt $menu.ui_height) {
                $menu.ui_height = $list_limit
            }
            $menu.pos.Y = $rawUI.CursorPosition.Y - $menu.ui_height - $config.height_from_menu_bottom_to_cursor_when_above
        }
        else {
            if ($menu.cursor_to_bottom -lt $menu.ui_height) {
                $menu.ui_height = $menu.cursor_to_bottom
            }
            $list_limit = if ($config.list_max_count_when_below -gt 0) { $config.list_max_count_when_below + 2 }else { 12 }
            if ($list_limit -lt $menu.ui_height) {
                $menu.ui_height = $list_limit
            }
            $menu.pos.Y = $rawUI.CursorPosition.Y + 1 + $config.height_from_menu_top_to_cursor_when_below
        }
        $menu.page_max_index = $menu.ui_height - 3
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_menu_buffer {
        param($startPos, $endPos)

        $top = New-Object System.Management.Automation.Host.Coordinates $startPos.X, $startPos.Y
        $bottom = New-Object System.Management.Automation.Host.Coordinates $endPos.X , $endPos.Y
        $buffer = $rawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $top, $bottom))
        @{
            top    = $top
            bottom = $bottom
            buffer = $buffer
        }
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_menu_list_buffer {
        param([int]$offset)

        $lines = $offset..($menu.ui_height - 3 + $offset)
        $content_box = foreach ($l in $lines) {
            $item = $menu.filter_list[$l]
            $text = $item.ListItemText -replace '\e\[[\d;]*[a-zA-Z]', ''
            $text = $text + $item.padSymbols
            $rest = $menu.list_max_width - $rawUI.LengthInBufferCells($text)
            if ($rest -ge 0) {
                $text + ' ' * $rest
            }
            else {
                $w = $text.Length + $rest
                if ($w -gt 0) {
                    $text.Substring(0, $w)
                }
                else {
                    $text.Substring(0, 25)
                }
            }
        }
        $rawUI.SetBufferContents(@{
                X = $menu.pos.X + 1
                Y = $menu.pos.Y + 1
            },
            $rawUI.NewBufferCellArray($content_box, $config.item_color, $bgColor)
        )
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_menu_filter_buffer {
        param([string]$filter)

        $char = $config.filter_symbol
        $middle = [System.Math]::Ceiling($char.Length / 2)
        $start = $char.Substring(0, $middle)
        $end = $char.Substring($middle)

        $rawUI.SetBufferContents(
            @{
                X = $menu.pos.X + 2
                Y = $menu.pos.Y
            },
            $rawUI.NewBufferCellArray(@(@($start, $filter, $end) -join ''), $config.filter_color, $bgColor)
        )
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_menu_status_buffer {
        $X = $menu.pos.X + 3
        if ($menu.is_show_above) {
            $Y = $rawUI.CursorPosition.Y - 1 - $config.height_from_menu_bottom_to_cursor_when_above
        }
        else {
            $Y = $menu.pos.Y + $menu.ui_height - 1
        }

        $current = "$(([string]($menu.selected_index + 1)).PadLeft($menu.filter_list.Count.ToString().Length, '0'))"
        $rawUI.SetBufferContents(@{ X = $X; Y = $Y }, $rawUI.NewBufferCellArray(@("$current$($config.status_symbol)$($menu.filter_list.Count)"), $config.status_color, $bgColor))
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_menu_tip_buffer {
        param([int]$index)

        if ($menu.is_show_above) {
            $start = 0
            $line = $menu.pos.Y
        }
        else {
            $start = $menu.pos.Y + $menu.ui_height
            $line = $rawUI.BufferSize.Height - $start
        }
        if ($line -gt 0) {
            $content = ' ' * $rawUI.BufferSize.Width
            $box = @($content) * $line
            $rawUI.SetBufferContents(
                @{
                    X = 0
                    Y = $start
                },
                $rawUI.NewBufferCellArray($box, $bgColor, $bgColor)
            )
        }

        if ($menu.is_show_tip) {
            if ($menu.is_show_above) {
                $rest_line = $menu.cursor_to_top - $menu.ui_height
            }
            else {
                $rest_line = $menu.cursor_to_bottom - $menu.ui_height
            }
            if ($rest_line -le 0) {
                return
            }

            $tip = $menu.filter_list[$index].ToolTip -join "`n"
            if ($null -ne $tip) {
                $json = $PSCompletions.completions[$PSCompletions.root_cmd]
                $info = $json.info

                $tip_arr = @()

                $lineWidth = $rawUI.BufferSize.Width - 1
                if ($menu.need_full_width) {
                    $x = 1
                }
                else {
                    if ($config.enable_tip_follow_cursor) {
                        $x = $menu.pos.X + 1
                        $lineWidth -= $rawUI.CursorPosition.X + 1
                    }
                    else {
                        $x = 1
                    }
                }

                $tips = $PSCompletions.replace_content($tip).Split("`n").Where({ $_ -ne '' })
                foreach ($v in $tips) {
                    $currentWidth = 0
                    $outputString = ''
                    $currentLine = ''
                    $char_record = @{}
                    $chars = $v.ToCharArray()
                    foreach ($char in $chars) {
                        if ($char_record.ContainsKey($char)) {
                            $charWidth = $char_record[$char]
                        }
                        else {
                            $charWidth = $rawUI.LengthInBufferCells($char)
                            $char_record[$char] = $charWidth
                        }

                        if ($currentWidth + $charWidth -gt $lineWidth) {
                            $outputString += $currentLine + "`n"
                            $currentLine = ''
                            $currentWidth = 0
                        }
                        $currentLine += $char
                        $currentWidth += $charWidth
                    }

                    $outputString += $currentLine

                    $tip_arr += ($outputString).Split("`n")
                }

                if ($tip_arr.Count -eq 0) {
                    return
                }

                $pos = @{
                    X = $x
                    Y = $menu.pos.Y + $menu.ui_height + 1
                }
                $full = $rest_line - $tip_arr.Count

                if ($menu.is_show_above) {
                    if ($full -lt 0) {
                        $pos.Y = 0
                        $maxIndex = $tip_arr.Count + $full - 1
                    }
                    else {
                        $pos.Y = $full
                        $maxIndex = $tip_arr.Count - 1
                    }
                    $tip_arr = $tip_arr[0..$maxIndex]
                }
                else {
                    if ($pos.Y -ge $rawUI.BufferSize.Height - 1) {
                        return
                    }
                }
                $rawUI.SetBufferContents($pos, $rawUI.NewBufferCellArray($tip_arr, $config.tip_color, $bgColor))
            }
        }
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_menu_selection {
        if ($menu.old_selection) {
            $rawUI.SetBufferContents($menu.old_selection.pos, $menu.old_selection.buffer)
        }

        $X = $menu.pos.X + 1
        $to_X = $X + $menu.list_max_width - 1

        # 当前页的第几个
        $Y = $menu.pos.Y + 1 + $menu.page_current_index

        # 根据坐标，生成需要被改变内容的矩形，也就是要被选中的项
        $Rectangle = New-Object System.Management.Automation.Host.Rectangle $X, $Y, $to_X, $Y

        # 通过矩形，获取到这个矩形中的原本的内容
        $LineBuffer = $rawUI.GetBufferContents($Rectangle)
        $menu.old_selection = @{
            pos    = @{
                X = $X
                Y = $Y
            }
            buffer = $LineBuffer
        }
        # 给原本的内容设置前景颜色和背景颜色
        # XXX: 对于多字节字符，需要过滤掉 Trailing 类型字符以确保正确渲染
        $LineBuffer = $LineBuffer.Where({ $_.BufferCellType -ne 'Trailing' })
        $content = foreach ($i in $LineBuffer) { $i.Character }
        $rawUI.SetBufferContents(@{ X = $X; Y = $Y }, $rawUI.NewBufferCellArray(@([string]::Join('', $content)), $config.selected_color, $config.selected_bgcolor))
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod move_menu_selection {
        param([bool]$isDown)

        $moveDirection = if ($isDown) { 1 } else { -1 }

        $is_move = if ($isDown) {
            $menu.page_current_index -lt $menu.page_max_index
        }
        else {
            $menu.page_current_index -gt 0
        }

        $new_selected_index = $menu.selected_index + $moveDirection

        if ($config.enable_list_loop) {
            $menu.selected_index = ($new_selected_index + $menu.filter_list.Count) % $menu.filter_list.Count
        }
        else {
            $menu.selected_index = if ($new_selected_index -lt 0) {
                0
            }
            elseif ($new_selected_index -ge $menu.filter_list.Count) {
                $menu.filter_list.Count - 1
            }
            else {
                $new_selected_index
            }
        }

        if ($is_move) {
            $menu.page_current_index = ($menu.page_current_index + $moveDirection) % ($menu.page_max_index + 1)
            if ($menu.page_current_index -lt 0) {
                $menu.page_current_index += $menu.page_max_index + 1
            }
            $menu.set_menu_selection()
            $menu.new_menu_status_buffer()
            $menu.new_menu_tip_buffer($menu.selected_index)
            $menu.handle_menu_data('edit')
            return
        }

        if ($config.enable_list_loop -or ($new_selected_index -ge 0 -and $new_selected_index -lt $menu.filter_list.Count)) {
            if ($isDown) {
                if ($menu.selected_index -eq 0) {
                    $menu.page_current_index -= $menu.page_max_index
                }
            }
            else {
                if ($menu.selected_index -eq $menu.filter_list.Count - 1) {
                    $menu.page_current_index += $menu.page_max_index
                }
            }

            $menu.offset = ($menu.offset + $moveDirection) % ($menu.filter_list.Count - $menu.page_max_index)
            if ($menu.offset -lt 0) {
                $menu.offset += $menu.filter_list.Count - $menu.page_max_index
            }

            $menu.old_selection = $null
            $menu.new_menu_list_buffer($menu.offset)
            $menu.set_menu_selection()
            $menu.new_menu_filter_buffer($menu.filter)
            $menu.new_menu_status_buffer()
            $menu.new_menu_tip_buffer($menu.selected_index)
            $menu.handle_menu_data('edit')
        }
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod reset_menu {
        param([bool]$clearAll = $true)
        if ($clearAll) {
            $menu.data.Clear()
            if ($menu.origin_full_buffer) {
                $rawUI.SetBufferContents($menu.origin_full_buffer.top, $menu.origin_full_buffer.buffer)
                $menu.origin_full_buffer = $null
            }
        }
        $menu.old_selection = $null
        $menu.offset = 0
        $menu.selected_index = 0
        $menu.page_current_index = 0
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_menu_data {
        param([string]$type)

        switch ($type) {
            add {
                $menu.data.Add(
                    @{
                        page_current_index = $menu.page_current_index
                        page_max_index     = $menu.page_max_index
                        selected_index     = $menu.selected_index
                        offset             = $menu.offset
                        filter             = $menu.filter
                        filter_list        = $menu.filter_list
                        old_selection      = $menu.old_selection.Clone()
                        old_full_buffer    = $menu.get_menu_buffer($menu.buffer_start, $menu.buffer_end)

                        # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
                        ui_height          = $menu.ui_height
                        pos_y              = $menu.pos.Y
                    }
                )
            }
            get {
                $data = $menu.data[-1]
                $menu.page_current_index = $data.page_current_index
                $menu.page_max_index = $data.page_max_index
                $menu.selected_index = $data.selected_index
                $menu.offset = $data.offset
                $menu.filter = $data.filter
                $menu.filter_list = $data.filter_list
                $menu.old_selection = $data.old_selection

                # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
                $menu.ui_height = $data.ui_height
                $menu.pos.Y = $data.pos_y
            }
            edit {
                $menu.data[-1] = @{
                    page_current_index = $menu.page_current_index
                    page_max_index     = $menu.page_max_index
                    selected_index     = $menu.selected_index
                    offset             = $menu.offset
                    filter             = $menu.filter
                    filter_list        = $menu.filter_list
                    old_selection      = $menu.old_selection.Clone()
                    old_full_buffer    = $menu.get_menu_buffer($menu.buffer_start, $menu.buffer_end)

                    # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
                    ui_height          = $menu.ui_height
                    pos_y              = $menu.pos.Y
                }
            }
        }
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_menu_output {
        param($item)

        $out = $item.CompletionText

        if ($PSCompletions.need_ignore_suffix) {
            return $out
        }

        # 不是由 TabExpansion2 获取的补全，即通过 psc add 添加的补全
        if ($null -eq $item.ResultType) {
            return "$out$suffix"
        }

        if ($item.ResultType -in @(
                [System.Management.Automation.CompletionResultType]::Method,
                [System.Management.Automation.CompletionResultType]::Property,
                [System.Management.Automation.CompletionResultType]::Variable,
                [System.Management.Automation.CompletionResultType]::Type,
                [System.Management.Automation.CompletionResultType]::Namespace
            )) {
            return $out
        }

        # Directory, registry key, or other container types
        if ($item.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            if ($config.enable_path_with_trailing_separator) {
                if ($out.Length -ge 1 -and $out[-1] -match "^['`"]$") {
                    if ($out.Length -ge 2 -and $out[-2] -match "^[/\\]$") {
                        return $out
                    }
                    return $out.Insert($out.Length - 1, $PSCompletions.separator)
                }
                return $out + $PSCompletions.separator
            }
            return $out
        }

        # File or other leaf items (e.g., registry values)
        # [System.Management.Automation.CompletionResultType]::ProviderItem

        # [System.Management.Automation.CompletionResultType]::Command

        # [System.Management.Automation.CompletionResultType]::ParameterName

        # [System.Management.Automation.CompletionResultType]::ParameterValue

        # if foreach switch ...
        # [System.Management.Automation.CompletionResultType]::Keyword

        # [System.Management.Automation.CompletionResultType]::Text

        return "$out$suffix"
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
        param($filter_list)

        if (!$filter_list) { return '' }

        $menu = $PSCompletions.menu
        $config = $PSCompletions.config
        $rawUI = $Host.UI.RawUI
        $bgColor = $rawUI.BackgroundColor

        $suffix = $config.completion_suffix

        $menu.pos = @{ X = 0; Y = 0 }

        $menu.ui_height = 0

        $menu.filter = ''  # 过滤的关键词

        $menu.page_current_index = 0 # 当前显示页中的索引

        $menu.selected_index = 0  # 当前选中项的实际索引

        $menu.offset = 0  # 索引的偏移量，用于滚动翻页

        # 记录每一次过滤的数据
        $menu.data = [System.Collections.Generic.List[System.Object]]::new()

        if ($menu.by_TabExpansion2) {
            $menu.is_show_tip = $config.enable_tip_when_enhance
        }
        else {
            $enable_tip = $config.comp_config[$PSCompletions.root_cmd].enable_tip
            if ($null -eq $enable_tip) {
                $menu.is_show_tip = $config.enable_tip
            }
            else {
                $menu.is_show_tip = $enable_tip
            }
        }

        if ($config.enable_list_full_width) {
            $menu.filter_list = @($filter_list)
            $menu.ui_width = $rawUI.BufferSize.Width
            $menu.list_max_width = $menu.ui_width - 2
            $menu.need_full_width = $true
        }
        else {
            $menu.filter_list = [System.Collections.Generic.List[System.Object]]::new($filter_list.Count)
            $maxWidth = $config.list_min_width
            foreach ($item in $filter_list) {
                $len = $rawUI.LengthInBufferCells($item.ListItemText + $item.padSymbols)
                if ($len -gt $maxWidth) {
                    $maxWidth = $len
                }
                $menu.filter_list.Add($item)
            }
            $menu.ui_width = $maxWidth + 2
            $menu.list_max_width = $maxWidth
            if ($menu.ui_width -gt $rawUI.BufferSize.Width) {
                $menu.ui_width = $rawUI.BufferSize.Width
                $menu.list_max_width = $menu.ui_width - 2
                $menu.need_full_width = $true
            }
            else {
                $menu.need_full_width = $null
            }
        }

        if ($config.enable_enter_when_single -and $menu.filter_list.Count -eq 1) {
            return $menu.handle_menu_output($menu.filter_list[0])
        }

        $current_encoding = [console]::OutputEncoding
        [console]::OutputEncoding = $PSCompletions.encoding

        $menu.cursor_to_bottom = $rawUI.BufferSize.Height - $rawUI.CursorPosition.Y - 1 - $config.height_from_menu_top_to_cursor_when_below
        $menu.cursor_to_top = $rawUI.CursorPosition.Y - $config.height_from_menu_bottom_to_cursor_when_above - 1

        $menu.is_show_above = $menu.cursor_to_top -gt $menu.cursor_to_bottom

        if ($menu.is_show_above) {
            $startY = 0
            $endY = $menu.cursor_to_top
        }
        else {
            $startY = $rawUI.CursorPosition.Y + 1
            $endY = $rawUI.BufferSize.Height - 1
        }

        $menu.buffer_start = New-Object System.Management.Automation.Host.Coordinates 0, $startY
        $menu.buffer_end = New-Object System.Management.Automation.Host.Coordinates ($rawUI.BufferSize.Width - 1), $endY

        $menu.parse_menu_list()

        # 如果解析后的菜单高度小于 3 (上下边框 + 1个补全项)
        if ($menu.ui_height -lt 3) {
            [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
            return ''
        }

        # 显示菜单之前，记录 buffer
        $menu.origin_full_buffer = $menu.get_menu_buffer($menu.buffer_start, $menu.buffer_end)

        # 显示菜单
        $menu.new_menu_border_buffer()
        $menu.new_menu_list_buffer($menu.offset)
        $menu.set_menu_selection()
        $menu.new_menu_filter_buffer($menu.filter)
        $menu.new_menu_status_buffer()
        $menu.new_menu_tip_buffer($menu.selected_index)

        $menu.handle_menu_data('add')

        :loop while (($PressKey = $rawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode) {
            $pressShift = 0x10 -band [int]$PressKey.ControlKeyState
            $pressCtrl = $PressKey.ControlKeyState -like '*CtrlPressed*'

            switch ($PressKey.VirtualKeyCode) {
                9 {
                    # 9: Tab
                    if ($menu.filter_list.Count -eq 1) {
                        $menu.reset_menu()
                        $menu.handle_menu_output($menu.filter_list[$menu.selected_index])
                        break loop
                    }
                    $menu.move_menu_selection(!$pressShift)
                    break
                }
                { $_ -eq 27 -or ($pressCtrl -and $_ -eq 67) } {
                    # 27: ESC
                    # 67: Ctrl + c
                    $menu.reset_menu()
                    ''
                    break loop
                }
                { $_ -in @(32, 13) } {
                    # 32: Space
                    # 13: Enter
                    $menu.handle_menu_output($menu.filter_list[$menu.selected_index])
                    $menu.reset_menu()
                    break loop
                }

                # 向上
                # 37: Up
                # 38: Left
                # 85: Ctrl + u
                # 80: Ctrl + p
                # 75: Ctrl + k
                { $_ -in @(37, 38) -or ($pressCtrl -and $_ -in @(85, 80, 75)) } {
                    $menu.move_menu_selection($false)
                    break
                }
                # 向下
                # 39: Right
                # 40: Down
                # 68: Ctrl + d
                # 78: Ctrl + n
                # 74: Ctrl + j
                { $_ -in @(39, 40) -or ($pressCtrl -and $_ -in @(68, 78, 74)) } {
                    $menu.move_menu_selection($true)
                    break
                }
                # filter character
                { $PressKey.Character } {
                    # remove
                    if ($PressKey.Character -eq 8) {
                        # 8: Backspace
                        if ($menu.filter) {
                            $menu.filter = $menu.filter.Substring(0, $menu.filter.Length - 1)
                        }
                        else {
                            $menu.reset_menu()
                            ''
                            break loop
                        }

                        if ($menu.data.Count -gt 1) {
                            $old_buffer = $menu.data[-2].old_full_buffer
                            $rawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                            $menu.data.RemoveAt($menu.data.Count - 1)
                        }
                        else {
                            $old_buffer = $menu.data[0].old_full_buffer
                            $rawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                            $menu.data.Clear()
                        }

                        $menu.handle_menu_data('get')
                    }
                    else {
                        # add
                        if ($menu.filter -match '\*$' -and $PressKey.Character -eq '*') {
                            break
                        }
                        $menu.filter += $PressKey.Character

                        $escapedFilter = $menu.filter -replace '(\[|\])', '`$1'
                        if ($escapedFilter.StartsWith('^')) {
                            $comparison = {
                                param($text)
                                $text -like $escapedFilter.Substring(1) + '*'
                            }
                        }
                        else {
                            $comparison = {
                                param($text)
                                $text -like "*$escapedFilter*"
                            }
                        }
                        $list = $menu.filter_list
                        $resultList = [System.Collections.Generic.List[System.Object]]::new($list.Count)
                        foreach ($f in $list) {
                            if ($comparison.Invoke($f.ListItemText)) {
                                $resultList.Add($f)
                            }
                        }
                        $menu.filter_list = $resultList.ToArray()

                        if (!$menu.filter_list) {
                            $menu.filter = $menu.data[-1].filter
                            $menu.filter_list = $menu.data[-1].filter_list
                        }
                        else {
                            $menu.reset_menu($false)
                            $menu.parse_menu_list()
                            $menu.new_menu_border_buffer()
                            $menu.new_menu_list_buffer($menu.offset)
                            $menu.new_menu_tip_buffer($menu.selected_index)
                            $menu.new_menu_status_buffer()
                            $menu.new_menu_filter_buffer($menu.filter)
                            $menu.set_menu_selection(0)

                            $menu.handle_menu_data('add')
                        }
                    }
                    break
                }
            }
        }
        [console]::OutputEncoding = $current_encoding
    }

    if ($PSEdition -eq 'Core') {
        Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_menu_border_buffer {
            $horizontal = $config.horizontal
            $vertical = $config.vertical
            $top_left = $config.top_left
            $bottom_left = $config.bottom_left
            $top_right = $config.top_right
            $bottom_right = $config.bottom_right

            $list_area = $menu.list_max_width
            $border_box = @(
                [string]$top_left + $horizontal * $list_area + $top_right
                @([string]$vertical + ' ' * $list_area + [string]$vertical) * ($menu.ui_height - 2)
                [string]$bottom_left + $horizontal * $list_area + $bottom_right
            )
            $rawUI.SetBufferContents($menu.pos, $rawUI.NewBufferCellArray($border_box, $config.border_color, $bgColor))
        }
    }
    else {
        Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_menu_border_buffer {
            # XXX: 在 Windows PowerShell 5.x 中，边框使用以下符号以处理兼容性问题
            $horizontal = '-'
            $vertical = '|'
            $top_left = '+'
            $bottom_left = '+'
            $top_right = '+'
            $bottom_right = '+'

            $list_area = $menu.list_max_width
            $border_box = @(
                [string]$top_left + $horizontal * $list_area + $top_right
                @([string]$vertical + ' ' * $list_area + [string]$vertical) * ($menu.ui_height - 2)
                [string]$bottom_left + $horizontal * $list_area + $bottom_right
            )
            $rawUI.SetBufferContents($menu.pos, $rawUI.NewBufferCellArray($border_box, $config.border_color, $bgColor))
        }
    }
}
else {
    # WSL/Unix...
    . $PSScriptRoot\completion\unix.ps1
}
. $PSScriptRoot\utils\$PSEdition.ps1

if (!(Test-Path $PSCompletions.path.order)) {
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod move_old_version {
        $version = (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent) -ErrorAction SilentlyContinue).Name | Sort-Object { [Version]$_ } -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\d+\.\d.*' }
        if ($version -is [array]) {
            $old_version = $version[-2]
            if ($old_version -match '^\d+\.\d.*' -and $old_version -ge '4') {
                $old_version_dir = Join-Path (Split-Path $PSCompletions.path.root -Parent) $old_version

                if (Test-Path "$old_version_dir/data.json") {
                    Move-Item "$old_version_dir/data.json" $PSCompletions.path.data -Force -ErrorAction SilentlyContinue
                }
                else {
                    $data = @{
                        list     = @()
                        alias    = @{}
                        aliasMap = @{}
                        config   = $PSCompletions.default_config
                    }
                    $data.config.comp_config = @{}
                    $items = Get-ChildItem -Path "$old_version_dir/completions" -ErrorAction SilentlyContinue
                    foreach ($_ in $items) {
                        $name = $_.Name
                        $data.list += $name
                        $data.alias.$name = @()
                        $path_alias = Join-Path $_.FullName 'alias.txt'
                        if (Test-Path $path_alias) {
                            $alias_list = $PSCompletions.get_content($path_alias)
                            foreach ($a in $alias_list) {
                                $data.alias.$name += $a
                                $data.aliasMap.$a = $name
                            }
                        }
                        else {
                            $path_config = Join-Path $_.FullName 'config.json'
                            $config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
                            if ($config.alias) {
                                foreach ($a in $config.alias) {
                                    $data.alias.$name += $a
                                    $data.aliasMap.$a = $name
                                }
                            }
                            else {
                                $data.alias.$name += $name
                                $data.aliasMap.$name = $name
                            }
                        }
                    }
                    $data | ConvertTo-Json -Depth 5 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
                }

                Get-ChildItem "$old_version_dir/completions" -Directory | ForEach-Object {
                    if ($_.Name -ne 'psc') {
                        Move-Item $_.FullName $PSCompletions.path.completions -Force -ErrorAction SilentlyContinue
                    }
                }
                Get-ChildItem "$old_version_dir/temp" | ForEach-Object {
                    if ($_.Name -ne 'completions.json') {
                        Move-Item $_.FullName $PSCompletions.path.temp -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        else {
            if (Test-Path $PSCompletions.path.data) {
                $data = $PSCompletions.get_raw_content($PSCompletions.path.data) | ConvertFrom-Json
                if (!$data.config) {
                    $PSCompletions.is_first_init = $true
                }
            }
            else {
                $PSCompletions.is_first_init = $true
            }
        }
    }
    $PSCompletions.ensure_dir($PSCompletions.path.completions)
    $PSCompletions.move_old_version()
    $PSCompletions.ensure_dir($PSCompletions.path.temp)
    $PSCompletions.ensure_dir($PSCompletions.path.order)
    $PSCompletions.is_init = $true
}

$PSCompletions.init_data()

if ($PSCompletions.is_init) {
    if ($PSCompletions.is_first_init) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.init_info))
    }
}
if (!$PSCompletions.config.enable_menu) {
    Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete
}
$PSCompletions.generate_completion()
$PSCompletions.handle_completion()
if ($PSCompletions.config.enable_auto_alias_setup) {
    # 使用特殊变量作为临时变量(如: $_,$args,$Matches,...)，避免污染全局
    $Matches = $PSCompletions.data.aliasMap.Keys
    foreach ($_ in $Matches) {
        $args = $PSCompletions.data.aliasMap[$_]
        if ($args -eq 'psc') {
            Set-Alias $_ $PSCompletions.config.function_name -Force -ErrorAction SilentlyContinue
        }
        elseif ($_ -ne $args) {
            Set-Alias $_ $args -Force -ErrorAction SilentlyContinue
        }
    }
    $Matches = $null
}
else {
    Set-Alias psc $PSCompletions.config.function_name -Force -ErrorAction SilentlyContinue
}

if ($PSCompletions.config.enable_module_update -notin @(0, 1)) {
    $PSCompletions.version_list = $PSCompletions.config.enable_module_update, $PSCompletions.version | Sort-Object { [version] $_ } -Descending -ErrorAction SilentlyContinue
    if ($PSCompletions.version_list[0] -ne $PSCompletions.version) {
        $PSCompletions.download_file("module/CHANGELOG.json", (Join-Path $PSCompletions.path.temp 'CHANGELOG.json'), $PSCompletions.urls + 'https://pscompletions.abgox.com')

        # XXX: 这里是为了避免 CompletionPredictor 模块引起的多次确认
        if (!$PSCompletions._write_update_confirm) {
            $PSCompletions._write_update_confirm = $true
            $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update))
        }
    }
    else {
        $PSCompletions.config.enable_module_update = 1
        $PSCompletions.data | ConvertTo-Json -Depth 5 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
    }
}
else {
    if (!$PSCompletions._show_update_info) {
        $PSCompletions._show_update_info = $true
        if ($PSCompletions.config.enable_completions_update) {
            if (($PSCompletions.update -or $PSCompletions.get_content($PSCompletions.path.change) -and !$PScompletions.is_init)) {
                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.update_info))
            }
        }
    }
}

$PSCompletions.start_job()
