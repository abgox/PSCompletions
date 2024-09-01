using namespace System.Management.Automation
$_ = Split-Path $PSScriptRoot -Parent
New-Variable -Name PSCompletions -Value @{
    version                 = '5.0.4'
    path                    = @{
        root             = $_
        completions      = Join-Path $_ 'completions'
        core             = Join-Path $_ 'core'
        completions_json = Join-Path $_ 'completions.json'
        data             = Join-Path $_ 'data.json'
        update           = Join-Path $_ 'update.txt'
        change           = Join-Path $_ 'change.txt'
    }
    order                   = [ordered]@{}
    language                = $PSUICulture
    encoding                = [console]::OutputEncoding
    wc                      = New-Object System.Net.WebClient
    menu                    = @{
        const = @{
            symbol_item = @('SpaceTab', 'WriteSpaceTab', 'OptionTab')
            line_item   = @('horizontal', 'vertical', 'top_left', 'bottom_left', 'top_right', 'bottom_right')
            color_item  = @('item_text', 'item_back', 'selected_text', 'selected_back', 'filter_text', 'filter_back', 'border_text', 'border_back', 'status_text', 'status_back', 'tip_text', 'tip_back')
            color_value = @('White', 'Black', 'Gray', 'DarkGray', 'Red', 'DarkRed', 'Green', 'DarkGreen', 'Blue', 'DarkBlue', 'Cyan', 'DarkCyan', 'Yellow', 'DarkYellow', 'Magenta', 'DarkMagenta')
            config_item = @(
                'trigger_key', 'between_item_and_symbol', 'status_symbol', 'filter_symbol', 'enable_menu', 'enable_menu_enhance', 'enable_tip', 'enable_tip_when_enhance', 'enable_completions_sort', 'enable_tip_follow_cursor', 'enable_list_follow_cursor', 'enable_tip_cover_buffer', 'enable_list_cover_buffer', 'enable_list_loop', 'enable_selection_with_margin', 'enable_enter_when_single', 'enable_prefix_match_in_filter', 'list_min_width', 'list_max_count_when_above', 'list_max_count_when_below', 'width_from_menu_left_to_item', 'width_from_menu_right_to_item', 'height_from_menu_bottom_to_cursor_when_above'
            )
        }
    }
    default_config          = [ordered]@{
        # config
        url                                          = ''
        language                                     = $PSUICulture
        enable_completions_update                    = 1
        enable_module_update                         = 1
        disable_cache                                = 0
        function_name                                = 'PSCompletions'

        # menu symbol
        SpaceTab                                     = '😄'
        WriteSpaceTab                                = '😎'
        OptionTab                                    = '🤔'

        # menu line
        horizontal                                   = '═'
        vertical                                     = '║'
        top_left                                     = '╔'
        bottom_left                                  = '╚'
        top_right                                    = '╗'
        bottom_right                                 = '╝'

        # menu color
        item_text                                    = 'Blue'
        item_back                                    = 'Black'
        selected_text                                = 'white'
        selected_back                                = 'DarkGray'
        filter_text                                  = 'Yellow'
        filter_back                                  = 'Black'
        border_text                                  = 'DarkGray'
        border_back                                  = 'Black'
        status_text                                  = 'Blue'
        status_back                                  = 'Black'
        tip_text                                     = 'Cyan'
        tip_back                                     = 'Black'

        # menu config
        trigger_key                                  = 'Tab'
        between_item_and_symbol                      = ' '
        status_symbol                                = '/'
        filter_symbol                                = '[]'

        enable_menu                                  = 1
        enable_menu_enhance                          = 1
        enable_tip                                   = 1
        enable_tip_when_enhance                      = 1
        enable_completions_sort                      = 1
        enable_tip_follow_cursor                     = 1
        enable_list_follow_cursor                    = 1
        enable_tip_cover_buffer                      = 1
        enable_list_cover_buffer                     = 0

        enable_list_loop                             = 1
        enable_selection_with_margin                 = 1
        enable_enter_when_single                     = 0
        enable_prefix_match_in_filter                = 0

        list_min_width                               = 10
        list_max_count_when_above                    = -1
        list_max_count_when_below                    = -1
        width_from_menu_left_to_item                 = 0
        width_from_menu_right_to_item                = 0
        height_from_menu_bottom_to_cursor_when_above = 0
    }
    # 每个补全都默认带有的配置项
    default_completion_item = @('language', 'enable_tip')
    config_item             = @('url', 'language', 'enable_completions_update', 'enable_module_update', 'disable_cache', 'function_name')
} -Option ReadOnly

if ($PSEdition -eq 'Core' -and !$IsWindows) {
    # WSL/Unix...
    . $PSScriptRoot\utils\Core.ps1
    . $PSScriptRoot\completion\unix.ps1
}
else {
    # Windows...
    . $PSScriptRoot\utils\$PSEdition.ps1
    . $PSScriptRoot\completion\win.ps1
    . $PSScriptRoot\menu\win.ps1
}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_completion {
    # 获取 json 数据
    if ($PSCompletions.job.State -eq 'Completed') {
        $PSCompletions.completions = Receive-Job $PSCompletions.job
        Remove-Job $PSCompletions.job
        $PSCompletions.job = $null
    }
    if (!$PSCompletions.completions.$root -or $PSCompletions.config.disable_cache) {
        $language = $PSCompletions.get_language($root)
        $PSCompletions.completions.$root = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$root/language/$language.json"))
    }

    $input_arr = [array]$input_arr

    $common_options = @()
    $common_options_with_next = @()
    foreach ($_ in $PSCompletions.completions.$root.common_options) {
        foreach ($a in $_.alias) {
            $common_options += $a
            if ($_.next) { $common_options_with_next += $a }
        }
        $common_options += $_.name
        if ($_.next) { $common_options_with_next += $_.name }
    }
    $PSCompletions.temp_WriteSpaceTab = @()
    $PSCompletions.temp_WriteSpaceTab += $common_options_with_next

    $PSCompletions.temp_WriteSpaceTab_and_SpaceTab = @()

    # 存储别名的映射，用于在过滤时允许别名
    $alias_map = @{}

    function getCompletions {
        $completions = @()

        $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
        $runspacePool.Open()
        $runspaces = @()

        $tasks = @(
            @{
                node     = $PSCompletions.completions.$root.root
                isOption = $false
            },
            @{
                node     = $PSCompletions.completions.$root.options
                isOption = $true
            }
        )
        foreach ($task in $tasks) {
            $runspace = [powershell]::Create().AddScript({
                    param($obj, $PSCompletions)
                    $completions = [System.Collections.Generic.List[System.Object]]@()
                    $_alias_map = @{}
                    $temp = @{
                        WriteSpaceTab              = @()
                        WriteSpaceTab_and_SpaceTab = @()
                    }
                    function _replace {
                        param ($data, $separator = '')
                        $data = $data -join $separator
                        $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
                        $matches = [regex]::Matches($data, $pattern)
                        foreach ($match in $matches) {
                            $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
                        }
                        if ($data -match $pattern) { (_replace $data) }else { return $data }
                    }
                    function parseCompletions {
                        param($node, [string]$pre, [bool]$isOption)
                        foreach ($_ in $node) {
                            $pad = if ($pre) { ' ' }else { '' }
                            $symbols = @()
                            if ($isOption) {
                                $symbols += 'OptionTab'
                            }
                            if ($_.next -or $_.options) {
                                $symbols += 'SpaceTab'
                                if ($isOption) {
                                    $symbols += 'WriteSpaceTab'
                                }
                            }
                            if ($_.symbol) {
                                $symbols += (_replace $_.symbol ' ') -split ' '
                            }
                            $symbols = $symbols | Select-Object -Unique

                            if ($symbols) {
                                if ('WriteSpaceTab' -in $symbols) {
                                    $temp.WriteSpaceTab += $_.name
                                    if ($_.alias) {
                                        foreach ($a in $_.alias) { $temp.WriteSpaceTab += $a }
                                    }
                                    if ('SpaceTab' -in $symbols) {
                                        $temp.WriteSpaceTab_and_SpaceTab += $_.name
                                        if ($_.alias) {
                                            foreach ($a in $_.alias) { $temp.WriteSpaceTab_and_SpaceTab += $a }
                                        }
                                    }
                                }
                            }

                            $symbols = foreach ($c in $symbols) { $PSCompletions.config.$c }
                            $symbols = $symbols -join ''
                            $padSymbols = if ($symbols) { "$($PSCompletions.config.between_item_and_symbol)$symbols" }else { '' }

                            $completions.Add(@{
                                    name           = $pre + $pad + $_.name
                                    ListItemText   = "$($_.name)$padSymbols"
                                    CompletionText = $_.name
                                    ToolTip        = $_.tip
                                })
                            if ($_.alias) {
                                if ($isOption) {
                                    foreach ($a in $_.alias) {
                                        $completions.Add(@{
                                                name           = $pre + $pad + $a
                                                ListItemText   = "$a$padSymbols"
                                                CompletionText = $a
                                                ToolTip        = $_.tip
                                            })
                                        if ($_.next) { parseCompletions $_.next ($pre + $pad + $a) }
                                    }
                                }
                                else {
                                    foreach ($a in $_.alias) {
                                        # 判断别名出现的位置
                                        $index = (($pre + $pad + $_.name) -split ' ').Length - 1
                                        # 用这个位置创建一个数组，将所有在这个位置出现的别名全部写入这个数组
                                        if (!$_alias_map.$index) { $_alias_map.$index = @() }
                                        $_alias_map.$index += @{
                                            name  = $_.name
                                            alias = $a
                                        }
                                        $completions.Add(@{
                                                name           = $pre + $pad + $a
                                                ListItemText   = "$a$padSymbols"
                                                CompletionText = $a
                                                ToolTip        = $_.tip
                                            })
                                    }
                                }
                            }
                            if ($_.next) { parseCompletions $_.next ($pre + $pad + $_.name) }
                            if ($_.options) { parseCompletions $_.options ($pre + $pad + $_.name) $true }
                        }
                    }
                    parseCompletions $obj.node '' $obj.isOption
                    @{
                        completions = $completions
                        alias_map   = $_alias_map
                        temp        = $temp
                    }
                }).AddArgument($task).AddArgument($PSCompletions)
            $runspace.RunspacePool = $runspacePool
            $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
        }

        # 等待所有任务完成
        foreach ($rs in $runspaces) {
            $result = $rs.Runspace.EndInvoke($rs.Job)
            $rs.Runspace.Dispose()
            $completions += $result.completions
            $PSCompletions.temp_WriteSpaceTab += $result.temp.WriteSpaceTab
            $PSCompletions.temp_WriteSpaceTab_and_SpaceTab += $result.temp.WriteSpaceTab_and_SpaceTab
            foreach ($a in $result.alias_map.Keys) {
                if ($alias_map.$a) {
                    $alias_map.$a += $result.alias_map.$a
                }
                else {
                    $alias_map.$a = $result.alias_map.$a
                }
            }
        }
        return $completions
    }
    function handleCompletions {
        param($completions)
        return $completions
    }
    function filterCompletions {
        param($completions, [string]$root)

        # 当这个 options 是 WriteSpaceTab 时，将下一个值直接过滤掉
        $need_skip = $false

        $filter_input_arr = @()
        foreach ($_ in $input_arr) {
            if ($_ -like '-*' -or $need_skip) {
                if ($need_skip) { $need_skip = $false }
                if ($_ -in $PSCompletions.temp_WriteSpaceTab) {
                    if ($input_arr[-1 - !$space_tab] -eq $_ -and $_ -in $PSCompletions.temp_WriteSpaceTab_and_SpaceTab) {
                        $need_add = $true
                    }
                    else {
                        $need_skip = $true
                    }
                }
            }
            else { $need_add = $true }
            if ($need_add -and $_ -notin $common_options) {
                $filter_input_arr += $_
                $need_add = $false
            }
        }

        if (!$space_tab) {
            # 如果是输入 -* 过程中触发的补全，则需要把最后一个 -* 加入其中
            if ($input_arr[-1] -like '-*') {
                $filter_input_arr += $input_arr[-1]
            }
        }

        if ($filter_input_arr.Count) {
            $match = if ($space_tab) { ' *' }else { '*' }
        }
        else {
            # 如果过滤出来为空，则是只是输入了根命令，没有输入其他内容
            $match = '*'
        }

        $alias_input_arr = $filter_input_arr

        # 循环命令的长度，针对每一个位置去 $alias_map 找到对应的数组，然后把数组里的值拿出来比对，如果有匹配的，替换掉原来的命令名
        # 用位置的好处是，这样遍历是依赖于命令的长度，而命令长度一般不长
        for ($i = 0; $i -lt $filter_input_arr.Count; $i++) {
            foreach ($obj in $alias_map.$i) {
                if ($obj.alias -eq $filter_input_arr[$i]) {
                    $alias_input_arr[$i] = $obj.name
                    break
                }
            }
        }

        $filter_list = @()

        $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
        $runspacePool.Open()
        $runspaces = @()

        foreach ($completions in $PSCompletions.split_array($completions, [Environment]::ProcessorCount, $true)) {
            $runspace = [powershell]::Create().AddScript({
                    param($completions, [array]$input_arr, [array]$filter_input_arr, [string]$match, [array]$alias_input_arr, [bool]$space_tab, $host_ui)
                    $max_width = 0
                    $results = @()
                    function get_length {
                        param([string]$str)
                        $host_ui.RawUI.NewBufferCellArray($str, $host_ui.RawUI.BackgroundColor, $host_ui.RawUI.BackgroundColor).LongLength
                    }
                    foreach ($completion in $completions) {
                        $matches = [regex]::Matches($completion.name, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                        $cmd = @()
                        foreach ($m in $matches) { $cmd += $m.Value }

                        # 判断选项是否使用过了，如果使用过了，$no_used 为 $true
                        # 这里的判断对于 --file="abc" 这样的命令无法使用，因为这里和用户输入的 "abc"是连着的
                        $no_used = if ($cmd[-1] -like '-*') {
                            $cmd[-1] -notin $input_arr
                        }
                        else { $true }

                        $isLike = ($completion.name -like ([WildcardPattern]::Escape($filter_input_arr -join ' ') + $match)) -or ($completion.name -like ([WildcardPattern]::Escape($alias_input_arr -join ' ') + $match))
                        if ($no_used -and $cmd.Count -eq ($filter_input_arr.Count + $space_tab) -and $isLike) {
                            $results += $completion
                            $max_width = [Math]::Max($max_width, (get_length $completion.ListItemText))
                        }
                    }
                    @{
                        results   = $results
                        max_width = $max_width
                    }
                }).AddArgument($completions).AddArgument($input_arr).AddArgument($filter_input_arr).AddArgument($match).AddArgument($alias_input_arr).AddArgument($space_tab).AddArgument($Host.UI)


            $runspace.RunspacePool = $runspacePool
            $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
        }

        # 等待所有任务完成
        foreach ($rs in $runspaces) {
            $result = $rs.Runspace.EndInvoke($rs.Job)
            $rs.Runspace.Dispose()
            if ($result.results) {
                $filter_list += $result.results
            }
            $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $result.max_width)
        }

        # 处理 common_options
        if ($PSCompletions.completions.$root.common_options) {
            function Get-PadSymbols {
                $symbols = @('OptionTab')
                if ($_.next) {
                    $symbols += 'SpaceTab'
                    $symbols += 'WriteSpaceTab'
                }
                if ($_.symbol) {
                    $symbols += $PSCompletions.replace_content($_.symbol, ' ') -split ' '
                }
                $symbols = $symbols | Select-Object -Unique

                $symbols = foreach ($c in $symbols) { $PSCompletions.config.$c }
                $symbols = $symbols -join ''
                if ($symbols) {
                    "$($PSCompletions.config.between_item_and_symbol)$symbols"
                }
                else {
                    ''
                }
            }
            if ($space_tab) {
                if ($input_arr[-1] -in $common_options_with_next -and ($input_arr -notlike "*$($input_arr[-1])*$($input_arr[-1])*" -or $input_arr -like "*$($input_arr[-1])")) {
                    $filter_list = @()
                    $filter = $PSCompletions.completions.$root.common_options.Where({ $_.name -eq $input_arr[-1] -or $_.alias -contains $input_arr[-1] })
                    foreach ($_ in $filter) {
                        foreach ($n in $_.next) {
                            $filter_list += @{
                                ListItemText   = $n.name
                                CompletionText = $n.name
                                ToolTip        = $n.tip
                            }
                            $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($n.name))
                        }
                    }
                }
                foreach ($_ in $PSCompletions.completions.$root.common_options) {
                    if ($_.name -notin $input_arr) {
                        $isExist = $false
                        $temp_list = @()
                        $name_with_symbol = "$($_.name)$(Get-PadSymbols)"
                        $temp_list += @{
                            ListItemText   = $name_with_symbol
                            CompletionText = $_.name
                            ToolTip        = $_.tip
                        }
                        $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($name_with_symbol))

                        foreach ($a in $_.alias) {
                            if ($a -notin $input_arr) {
                                $name_with_symbol = "$a$(Get-PadSymbols)"
                                $temp_list += @{
                                    ListItemText   = $name_with_symbol
                                    CompletionText = $a
                                    ToolTip        = $_.tip
                                }
                                $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($name_with_symbol))
                            }
                            else {
                                $temp_list = @()
                                break
                            }
                        }
                        $filter_list += $temp_list
                    }
                }
            }
            else {
                if ($input_arr[-2] -in $common_options_with_next -and $input_arr -notlike "*$($input_arr[-2])*$($input_arr[-2])*") {
                    $filter_list = @()
                    $filter = $PSCompletions.completions.$root.common_options.Where({ $_.name -eq $input_arr[-2] -or $_.alias -contains $input_arr[-2] })
                    foreach ($_ in $filter) {
                        foreach ($n in $_.next) {
                            if ($n.name -like "$($input_arr[-1])*") {
                                $filter_list += @{
                                    ListItemText   = $n.name
                                    CompletionText = $n.name
                                    ToolTip        = $n.tip
                                }
                                $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($n.name))
                            }
                        }
                    }
                }
                foreach ($_ in $PSCompletions.completions.$root.common_options) {
                    if ($_.name -notin $input_arr -and $_.name -like "$($input_arr[-1])*") {
                        $name_with_symbol = "$($_.name)$(Get-PadSymbols)"
                        $filter_list += @{
                            ListItemText   = $name_with_symbol
                            CompletionText = $_.name
                            ToolTip        = $_.tip
                        }
                        $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($name_with_symbol))
                    }
                    foreach ($a in $_.alias) {
                        if ($a -notin $input_arr -and $a -like "$($input_arr[-1])*") {
                            $name_with_symbol = "$a$(Get-PadSymbols)"
                            $filter_list += @{
                                ListItemText   = $name_with_symbol
                                CompletionText = $a
                                ToolTip        = $_.tip
                            }
                            $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($name_with_symbol))
                        }
                    }
                }
            }
        }
        return $filter_list
    }

    if ($PSCompletions.config.comp_config.$root.disable_hooks -ne $null) {
        # 使用 hooks 覆盖默认的函数，实现在一些特殊的需求，比如一些补全的动态加载
        if ($PSCompletions.config.comp_config.$root.disable_hooks -ne 1) {
            . "$($PSCompletions.path.completions)/$root/hooks.ps1"
        }
    }
    $completions = getCompletions
    $completions = handleCompletions $completions
    $filter_list = filterCompletions $completions $root

    # 排序
    if ($PSCompletions.config.enable_completions_sort) {
        $path_order = "$($PSCompletions.path.completions)/$root/order.json"
        if ($PSCompletions.order."$($root)_job") {
            if ($PSCompletions.order."$($root)_job".State -eq 'Completed') {
                $PSCompletions.order.$root = Receive-Job $PSCompletions.order."$($root)_job"
                Remove-Job $PSCompletions.order."$($root)_job"
                $PSCompletions.order.Remove("$($root)_job")
            }
        }
        else {
            if (Test-Path $path_order) {
                $PSCompletions.order.$root = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path_order))
            }
            else {
                $PSCompletions.order.$root = $null
            }
        }
        $order = $PSCompletions.order.$root
        if ($order) {
            $filter_list = $filter_list | Sort-Object {
                $o = $order.$($_.name -join ' ')
                if ($o) { $o }else { 999999999 }
            }
        }
        $PSCompletions.order_job($completions, (Get-PSReadLineOption).HistorySavePath, $root, $path_order)
    }
    return $filter_list
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod split_array {
    <#
    .Synopsis
        分割数组
    .Description
        三个参数:
        $array: 数组
        $count: 每个数组的元素个数
        $by_count: 如果此值为 $true, 则 $count 为指定的数组个数，否则为每个数组的元素个数
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
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_file {
    param([string]$path)
    if (!(Test-Path $path)) { New-Item -ItemType File $path > $null }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_dir {
    param([string]$path)
    if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod join_path {
    $res = $args[0]
    for ($i = 1; $i -lt $args.Count; $i++) {
        $res = Join-Path $res $args[$i]
    }
    $res
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_language {
    param ([string]$completion)
    $path_config = "$($PSCompletions.path.completions)/$completion/config.json"
    $content_config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
    if ($PSCompletions.config.comp_config.$completion.language) {
        $config_language = $PSCompletions.config.comp_config.$completion.language
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
    $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
    $matches = [regex]::Matches($data, $pattern)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
    }
    if ($data -match $pattern) { $PSCompletions.replace_content($data) }else { return $data }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod write_with_color {
    param([string]$str)
    $color_list = @()
    $str = $str -replace "`n", 'n&&_n_n&&'
    $str_list = foreach ($_ in ($str -split '(<\@[^>]+>.*?(?=<\@|$))').Where({ $_ -ne '' })) {
        if ($_ -match '<\@([\s\w]+)>(.*)') {
            ($matches[2] -replace 'n&&_n_n&&', "`n") -replace '^<\@>', ''
            $color = $matches[1] -split ' '
            $color_list += @{
                color   = $color[0]
                bgcolor = $color[1]
            }
        }
        else {
            ($_ -replace 'n&&_n_n&&', "`n") -replace '^<\@>', ''
            $color_list += @{}
        }
    }
    $str_list = [array]$str_list
    for ($i = 0; $i -lt $str_list.Count; $i++) {
        $color = $color_list[$i].color
        $bgcolor = $color_list[$i].bgcolor
        if ($color) {
            if ($bgcolor) {
                Write-Host $str_list[$i] -f $color -b $bgcolor -NoNewline
            }
            else {
                Write-Host $str_list[$i] -f $color -NoNewline
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
    if ($str_list -is [string]) {
        $str_list = $str_list -split "`n"
    }
    $i = 0
    $need_less = [System.Console]::WindowHeight -lt ($str_list.Count + 2)
    if ($need_less) {
        $lines = $str_list.Count - $show_line
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.less_tip))
        while ($i -lt $str_list.Count -and $i -lt $show_line) {
            Write-Host $str_list[$i] -f $color
            $i++
        }
        while ($i -lt $str_list.Count) {
            $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
            if ($keyCode -ne 13) {
                break
            }
            Write-Host $str_list[$i] -f $color
            $i++
        }
        $end = if ($i -lt $str_list.Count) { $false }else { $true }
        if ($end) {
            Write-Host ' '
            Write-Host '(End)' -f Black -b White -NoNewline
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
        foreach ($_ in $str_list) { Write-Host $_ -f $color }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod show_with_less_table {
    param (
        [array]$str_list,
        [array]$header = @('key', 'value', 5),
        [scriptblock]$do = {},
        [int]$show_line = [System.Console]::WindowHeight - 7
    )
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
                Write-Host $str_list[$i].content -f $str_list[$i].color -b $str_list[$i].bgColor
            }
            else {
                Write-Host $str_list[$i].content -f $str_list[$i].color
            }
            $i++
        }
        while ($i -lt $str_list.Count) {
            $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
            if ($keyCode -ne 13) {
                break
            }
            if ($str_list[$i].bgColor) {
                Write-Host $str_list[$i].content -f $str_list[$i].color -b $str_list[$i].bgColor
            }
            else { Write-Host $str_list[$i].content -f $str_list[$i].color }
            $i++
        }
        $end = if ($i -lt $str_list.Count) { $false }else { $true }
        if ($end) {
            Write-Host ' '
            Write-Host '(End)' -f Black -b White -NoNewline
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
                Write-Host $_.content -f $_.color -b $_.bgColor[2]
            }
            else {
                Write-Host $_.content -f $_.color
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod confirm_do {
    param ([string]$tip, [scriptblock]$confirm_event, [bool]$write_empty_line = $true)
    $PSCompletions.write_with_color($PSCompletions.replace_content($tip))

    while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode) {
        if ($PressKey.ControlKeyState -notlike '*CtrlPressed*') {
            if ($write_empty_line) { Write-Host '' }
            if ($PressKey.VirtualKeyCode -eq 13) {
                # 13: Enter
                & $confirm_event
                return $true
            }
            else {
                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.confirm_cancel))
                return $false
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_list {
    if (!(Test-Path $PSCompletions.path.completions_json)) {
        @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
    }
    $current_list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list
    try {
        $content = (Invoke-WebRequest -Uri "$($PSCompletions.url)/completions.json").Content | ConvertFrom-Json

        $remote_list = $content.list

        $diff = Compare-Object $remote_list $current_list -PassThru
        if ($diff) {
            $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8
            $content | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
            $PSCompletions.list = $remote_list
        }
        else {
            Clear-Content $PSCompletions.path.change -Force
            $PSCompletions.list = $current_list
        }
        return $remote_list
    }
    catch {
        $PSCompletions.list = $current_list
        $PSCompletions._invalid_url = "$($PSCompletions.url)/completions.json"
        return $false
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_file {
    param([string]$url, [string]$file)
    try {
        $PSCompletions.wc.DownloadFile($url, $file)
    }
    catch {
        if ($PSCompletions.info) {
            $download_info = @{
                url  = $url
                file = $file
            }
            $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.err.download_file))
        }
        else {
            Write-Host "File ($(Split-Path $url -Leaf)) download failed, please check your network connection or try again later." -ForegroundColor Red
            Write-Host "File download Url: $url" -ForegroundColor Red
            Write-Host "File save path: $file" -ForegroundColor Red
            Write-Host "If you are sure that it is not a network problem, please submit an issue`n" -ForegroundColor Red
        }
        throw
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod add_completion {
    param (
        [string]$completion,
        [bool]$log = $true,
        [bool]$is_update = $true
    )
    $url = "$($PSCompletions.url)/completions/$completion"

    $is_update = (Test-Path "$($PSCompletions.path.completions)/$completion") -and $is_update

    $completion_dir = Join-Path $PSCompletions.path.completions $completion

    $PSCompletions.ensure_dir($PSCompletions.path.completions)
    $PSCompletions.ensure_dir($completion_dir)
    $PSCompletions.ensure_dir((Join-Path $completion_dir 'language'))

    $download_info = @{
        url  = "$url/config.json"
        file = Join-Path $completion_dir 'config.json'
    }
    $PSCompletions.download_file($download_info.url, $download_info.file)

    $config = $PSCompletions.get_content("$completion_dir/config.json") | ConvertFrom-Json

    $files = @(
        @{
            Uri     = "$url/guid.txt"
            OutFile = Join-Path $completion_dir 'guid.txt'
        }
    )
    foreach ($_ in $config.language) {
        $files += @{
            Uri     = "$url/language/$_.json"
            OutFile = $PSCompletions.join_path($completion_dir, 'language', "$_.json")
        }
    }
    if ($config.hooks) {
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
            $PSCompletions.wc.DownloadFile($download_info.url, $download_info.file)
        }
        catch {
            $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.err.download_file))
            Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue
            throw
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
    if (!$PSCompletions.data.alias.$completion) {
        $PSCompletions.data.alias.$completion = @()
    }

    if ($config.alias) {
        foreach ($a in $config.alias) {
            if ($a -notin $PSCompletions.data.alias.$completion) {
                $PSCompletions.data.alias.$completion += $a
                $PSCompletions.data.aliasMap.$a = $completion
                $PSCompletions._need_update_data = $true
            }
        }
    }
    else {
        if ($completion -notin $PSCompletions.data.alias.$completion) {
            $PSCompletions.data.alias.$completion += $completion
            $PSCompletions.data.aliasMap.$completion = $completion
            $PSCompletions._need_update_data = $true
        }
    }
    $language = $PSCompletions.get_language($completion)
    $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$completion_dir/language/$language.json"))
    if (!$PSCompletions.completions) {
        $PSCompletions.completions = @{}
    }
    $PSCompletions.completions.$completion = $json

    if ($log) { $PSCompletions.write_with_color($PSCompletions.replace_content($done)) }

    if ($json.config) {
        if (!$PSCompletions.config.comp_config.$completion) {
            $PSCompletions.config.comp_config.$completion = @{}
        }
        foreach ($_ in $json.config) {
            if (!($PSCompletions.config.comp_config.$completion.$($_.name))) {
                $PSCompletions.config.comp_config.$completion.$($_.name) = $_.value
                $PSCompletions._need_update_data = $true
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod init_data {
    $PSCompletions.completions = @{}

    if (Test-Path $PSCompletions.path.data) {
        $PSCompletions.data = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($PSCompletions.path.data))
    }
    else {
        $data = @{
            list     = @()
            alias    = @{}
            aliasMap = @{}
            config   = $PSCompletions.default_config
        }
        $data.config.comp_config = @{}
        foreach ($_ in Get-ChildItem -Path $PSCompletions.path.completions -Directory) {
            $name = $_.Name
            $data.list += $name
            $data.alias.$name = @()
            $path_config = Join-Path $_.FullName 'config.json'
            if (!(Test-Path $path_config)) {
                $PSCompletions.add_completion($name)
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
            $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($_.FullName)/language/$language.json"))
            $data.config.comp_config.$name = @{}
            foreach ($_ in $json.config) {
                $data.config.comp_config.$name.$($_.name) = $_.value
            }
        }
        $data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
        $PSCompletions.data = $data
    }
    $PSCompletions.config = $PSCompletions.data.config
    $PSCompletions.language = $PSCompletions.config.language

    if ($PSCompletions.config.url) {
        $PSCompletions.url = $PSCompletions.config.url
    }
    else {
        if ($PSCompletions.language -eq 'zh-CN') {
            $PSCompletions.url = 'https://gitee.com/abgox/PSCompletions/raw/main'
        }
        else {
            $PSCompletions.url = 'https://raw.githubusercontent.com/abgox/PSCompletions/main'
        }
    }

    $PSCompletions.list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list

    $PSCompletions.update = $PSCompletions.get_content($PSCompletions.path.update)
    if ($PSCompletions._update_version -or 'psc' -notin $PSCompletions.data.list) {
        $PSCompletions.add_completion('psc', $false, $false)
        $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
        $PSCompletions._update_version = $null
    }
    if (!$PSCompletions.info) {
        if ($PSCompletions.completions.psc.info) {
            $PSCompletions.info = $PSCompletions.completions.psc.info
        }
        else {
            $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }
            $PSCompletions.info = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/psc/language/$language.json")).info
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_length {
    param([string]$str)
    $Host.UI.RawUI.NewBufferCellArray($str, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor).LongLength
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_powershell_menu {
    param([array]$filter_list)
    if ($Host.UI.RawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        ''
        return
    }

    # is_show_tip
    if ($PSCompletions.current_cmd) {
        $json = $PSCompletions.completions.$($PSCompletions.current_cmd)
        $info = $json.info

        $enable_tip = $PSCompletions.config.comp_config.$($PSCompletions.current_cmd).enable_tip
        if ($enable_tip -ne $null) {
            $PSCompletions.menu.is_show_tip = $enable_tip -eq 1
        }
        else {
            $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip -eq 1
        }
    }
    else {
        $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip -eq 1
    }

    if ($PSCompletions.menu.is_show_tip) {
        foreach ($_ in $filter_list) {
            if ($_.ToolTip) {
                $tip = $PSCompletions.replace_content($_.ToolTip)
                $tip_arr = $tip -split "`n"
            }
            else {
                $tip = ' '
                $tip_arr = @()
            }
            $PSCompletions.menu.tip_max_height = [Math]::Max($PSCompletions.menu.tip_max_height, $tip_arr.Count)
            [CompletionResult]::new($_.CompletionText, $_.ListItemText, 'ParameterValue', $tip)
        }
    }
    else {
        foreach ($_ in $filter_list) {
            [CompletionResult]::new($_.CompletionText, $_.ListItemText, 'ParameterValue', ' ')
        }
    }
    $PSCompletions.current_cmd = $null
}

if (!(Test-Path (Join-Path $PSCompletions.path.core '.temp'))) {
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod move_old_version {
        $version = (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent) -ErrorAction SilentlyContinue).Name | Sort-Object { [Version]$_ } -ErrorAction SilentlyContinue
        if ($version -is [array]) {
            $old_version = $version[-2]
            if ($old_version -match '^\d+\.\d.*' -and $old_version -ge '4') {
                $PSCompletions._update_version = $true
                $old_version_dir = Join-Path (Split-Path $PSCompletions.path.root -Parent) $old_version
                $PSCompletions.ensure_dir($PSCompletions.path.completions)

                if (Test-Path "$old_version_dir/data.json") {
                    foreach ($_ in Get-ChildItem "$old_version_dir/completions" -Directory -ErrorAction SilentlyContinue) {
                        if ($_.Name -ne 'psc') {
                            Move-Item $_.FullName $PSCompletions.path.completions -Force -ErrorAction SilentlyContinue
                        }
                    }
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
                    foreach ($_ in Get-ChildItem "$old_version_dir/completions" -Directory -ErrorAction SilentlyContinue) {
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

                        $path_data_config = "$old_version_dir/config.json"
                        if (Test-Path $path_data_config) {
                            $configMap = @{
                                url                          = 'url'
                                language                     = 'language'
                                update                       = 'enable_completions_update'
                                module_update                = 'enable_module_update'
                                disable_cache                = 'disable_cache'
                                function_name                = 'function_name'
                                symbol_SpaceTab              = 'SpaceTab'
                                symbol_WriteSpaceTab         = 'WriteSpaceTab'
                                symbol_OptionTab             = 'OptionTab'
                                menu_line_horizontal         = 'horizontal'
                                menu_line_vertical           = 'vertical'
                                menu_line_top_left           = 'top_left'
                                menu_line_bottom_left        = 'bottom_left'
                                menu_line_top_right          = 'top_right'
                                menu_line_bottom_right       = 'bottom_right'
                                menu_color_item_text         = 'item_text'
                                menu_color_item_back         = 'item_back'
                                menu_color_selected_text     = 'selected_text'
                                menu_color_selected_back     = 'selected_back'
                                menu_color_filter_text       = 'filter_text'
                                menu_color_filter_back       = 'filter_back'
                                menu_color_border_text       = 'border_text'
                                menu_color_border_back       = 'border_back'
                                menu_color_status_text       = 'status_text'
                                menu_color_status_back       = 'status_back'
                                menu_color_tip_text          = 'tip_text'
                                menu_color_tip_back          = 'tip_back'
                                menu_trigger_key             = 'trigger_key'
                                menu_between_item_and_symbol = 'between_item_and_symbol'
                                menu_status_symbol           = 'status_symbol'
                                menu_filter_symbol           = 'filter_symbol'
                                menu_enable                  = 'enable_menu'
                                menu_enhance                 = 'enable_menu_enhance'
                                menu_show_tip                = 'enable_tip'
                                menu_show_tip_when_enhance   = 'enable_tip_when_enhance'
                                menu_completions_sort        = 'enable_completions_sort'
                                menu_tip_follow_cursor       = 'enable_tip_follow_cursor'
                                menu_list_follow_cursor      = 'enable_list_follow_cursor'
                                menu_tip_cover_buffer        = 'enable_tip_cover_buffer'
                                menu_list_cover_buffer       = 'enable_list_cover_buffer'
                                menu_is_loop                 = 'enable_list_loop'
                                menu_selection_with_margin   = 'enable_selection_with_margin'
                                enter_when_single            = 'enable_enter_when_single'
                                menu_is_prefix_match         = 'enable_prefix_match_in_filter'
                                menu_list_min_width          = 'list_min_width'
                                menu_above_list_max_count    = 'list_max_count_when_above'
                                menu_below_list_max_count    = 'list_max_count_when_below'
                                menu_list_margin_left        = 'width_from_menu_left_to_item'
                                menu_list_margin_right       = 'width_from_menu_right_to_item'
                                menu_above_margin_bottom     = 'height_from_menu_bottom_to_cursor_when_above'
                            }

                            $data_config = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path_data_config))
                            foreach ($c in $data_config.Keys) {
                                if ($configMap[$c]) {
                                    $data.config.$($configMap[$c]) = $data_config.$c
                                }
                            }
                        }
                        if ($_.Name -ne 'psc') {
                            Move-Item $_.FullName $PSCompletions.path.completions -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
                }
                Move-Item "$old_version_dir/update.txt" $PSCompletions.path.update -Force -ErrorAction SilentlyContinue
                Move-Item "$old_version_dir/change.txt" $PSCompletions.path.change -Force -ErrorAction SilentlyContinue
                Move-Item "$old_version_dir/completions.json" $PSCompletions.path.completions_json -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            $PSCompletions.is_first_init = $true
        }
    }
    $PSCompletions.move_old_version()
    $null = New-Item (Join-Path $PSCompletions.path.core '.temp') -Force
}

$PSCompletions.init_data()

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete
    $PSCompletions.generate_completion()
    $PSCompletions.handle_completion()
}

if ($PSCompletions.is_first_init) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.init_info))
}

foreach ($_ in $PSCompletions.data.aliasMap.Keys) {
    if ($PSCompletions.data.aliasMap.$_ -eq 'psc') {
        Set-Alias $_ $PSCompletions.config.function_name -ErrorAction SilentlyContinue
    }
    else {
        if ($_ -ne $PSCompletions.data.aliasMap.$_) {
            Set-Alias $_ $PSCompletions.data.aliasMap.$_ -ErrorAction SilentlyContinue
        }
    }
}

if ($PSCompletions.config.enable_module_update -match '^\d+\.\d.*') {
    $PSCompletions.version_list = $PSCompletions.config.enable_module_update, $PSCompletions.version | Sort-Object { [version] $_ } -Descending
    if ($PSCompletions.version_list[0] -ne $PSCompletions.version) {
        $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/module/CHANGELOG.json", (Join-Path $PSCompletions.path.core 'CHANGELOG.json'))
        $null = $PSCompletions.confirm_do($PSCompletions.info.module.update, {
                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.updating))
                Update-Module PSCompletions -RequiredVersion $PSCompletions.version_list[0] -Force -ErrorAction Stop
            })
    }
    else {
        $PSCompletions.config.enable_module_update = 1
        $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
    }
}
else {
    if ($PSCompletions.config.enable_completions_update -eq 1) {
        if ($PSCompletions.update -or $PSCompletions.get_content($PSCompletions.path.change)) {
            $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.update_info))
        }
    }
}

$PSCompletions.start_job()
