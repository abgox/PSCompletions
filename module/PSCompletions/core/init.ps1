using namespace System.Management.Automation
$_ = Split-Path $PSScriptRoot -Parent
New-Variable -Name PSCompletions -Value @{
    version                 = '5.2.4'
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
    }
    order                   = [ordered]@{}
    root_cmd                = ''
    completions_data        = @{}
    guid                    = [guid]::NewGuid().Guid
    language                = $PSUICulture
    encoding                = [console]::OutputEncoding
    separator               = [System.IO.Path]::DirectorySeparatorChar
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
        SpaceTab                                     = '»'
        WriteSpaceTab                                = '!'
        OptionTab                                    = '?'

        # menu line
        horizontal                                   = [string][char]9552 # ═
        vertical                                     = [string][char]9553 # ║
        top_left                                     = [string][char]9556 # ╔
        bottom_left                                  = [string][char]9562 # ╚
        top_right                                    = [string][char]9559 # ╗
        bottom_right                                 = [string][char]9565 # ╝

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

if ($IsWindows -or $PSEdition -eq 'Desktop') {
    # Windows...
    . $PSScriptRoot\completion\win.ps1
    . $PSScriptRoot\menu\win.ps1
}
else {
    # WSL/Unix...
    . $PSScriptRoot\completion\unix.ps1
}
. $PSScriptRoot\utils\$PSEdition.ps1

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod return_completion {
    param([string]$name, $tip = ' ', [array]$symbols)
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
        $special_options = @{
            WriteSpaceTab              = @()
            WriteSpaceTab_and_SpaceTab = @()
        }
        function parseJson($cmds, $obj, $cmdO, [switch]$isOption) {
            if ($obj[$cmdO].$guid -eq $null) {
                $obj[$cmdO] = @{
                    $guid = @()
                }
            }
            foreach ($cmd in $cmds) {
                $symbols = @()
                if ($isOption) {
                    $symbols += 'OptionTab'
                }
                if ($cmd.next -is [array] -or $cmd.options -is [array]) {
                    if ($isOption) {
                        $symbols += 'WriteSpaceTab'
                    }
                    if ($cmd.next.Count -or $cmd.options.Count) {
                        $symbols += 'SpaceTab'
                    }
                }
                if ($cmd.symbol) {
                    $symbols += $PSCompletions.replace_content($cmd.symbol, ' ') -split ' '
                    $symbols = $symbols | Select-Object -Unique
                }
                $alias_list = $cmd.alias + $cmd.name

                $obj.$cmdO.$guid += @{
                    CompletionText = $cmd.name
                    ListItemText   = $cmd.name
                    ToolTip        = $cmd.tip
                    symbols        = $symbols
                    alias          = $alias_list
                }

                foreach ($alias in $cmd.alias) {
                    $obj.$cmdO.$guid += @{
                        CompletionText = $alias
                        ListItemText   = $alias
                        ToolTip        = $cmd.tip
                        symbols        = $symbols
                        alias          = $alias_list
                    }
                }

                if ($symbols) {
                    if ('WriteSpaceTab' -in $symbols) {
                        $pad = if ($cmdO -in @('rootOptions', 'commonOptions')) { ' ' }else { $cmdO + ' ' }
                        $special_options.WriteSpaceTab += $pad + $cmd.name
                        if ($cmd.alias) {
                            foreach ($a in $cmd.alias) { $special_options.WriteSpaceTab += $pad + $a }
                        }
                        if ('SpaceTab' -in $symbols) {
                            $special_options.WriteSpaceTab_and_SpaceTab += $pad + $cmd.name
                            if ($cmd.alias) {
                                foreach ($a in $cmd.alias) { $special_options.WriteSpaceTab_and_SpaceTab += $pad + $a }
                            }
                        }
                    }
                }
                if ($cmd.options) {
                    parseJson $cmd.options $obj.$cmdO "$($cmd.name)" -isOption
                    foreach ($alias in $cmd.alias) {
                        parseJson $cmd.options $obj.$cmdO "$($alias)" -isOption
                    }
                }
                if ($cmd.next -or 'WriteSpaceTab' -in $symbols) {
                    parseJson $cmd.next $obj.$cmdO "$($cmd.name)"
                    foreach ($alias in $cmd.alias) {
                        parseJson $cmd.next $obj.$cmdO "$($alias)"
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
        $PSCompletions.completions_data."$($root)_WriteSpaceTab" = $special_options.WriteSpaceTab | Select-Object -Unique
        $PSCompletions.completions_data."$($root)_WriteSpaceTab_and_SpaceTab" = $special_options.WriteSpaceTab_and_SpaceTab | Select-Object -Unique
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

            $commonOptions = $PSCompletions.completions_data."$($root)_common_options"
            $WriteSpaceTab = $PSCompletions.completions_data."$($root)_WriteSpaceTab"
            $WriteSpaceTab_and_SpaceTab = $PSCompletions.completions_data."$($root)_WriteSpaceTab_and_SpaceTab"

            foreach ($_ in $input_arr) {
                if ($need_skip) {
                    if ($_ -like '-*') {
                        if ($_ -eq $last_item) {
                            $filter_input_arr += $_
                        }
                    }
                    else {
                        $need_skip = $false
                        continue
                    }
                }
                else {
                    $pad = if ($_ -in $commonOptions) { '' } else { $pre_cmd }
                    if ($_ -like '-*') {
                        if ("$pad $_" -in $WriteSpaceTab) {
                            if ("$pad $_" -in $WriteSpaceTab_and_SpaceTab) {
                                # 如果选项是最后一个
                                if ($_ -eq $last_item) {
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

            if ($space_tab) {
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
                    $data = $PSCompletions.completions_data.$root.commonOptions.$last_item.$guid
                    if (!$data.Count) {
                        $data = $PSCompletions.completions_data.$root.rootOptions.$last_item.$guid
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
                            if ($completions.root.$guid) {
                                $filter_list += $completions.root.$guid
                            }
                            if ($completions.rootOptions.$guid) {
                                $filter_list += $completions.rootOptions.$guid
                            }
                            if ($completions.commonOptions.$guid) {
                                $filter_list += $completions.commonOptions.$guid
                            }
                        }
                    }
                }
                else {
                    if ($last_item -in $PSCompletions.completions_data."$($root)_common_options") {
                        $filter_list = $PSCompletions.completions_data.$root.commonOptions.$last_item.$guid
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
    if ($PSCompletions.config.disable_cache -eq 1) {
        $PSCompletions.completions.$root = $null
        $PSCompletions.completions_data.$root = $null
    }

    if (!$PSCompletions.completions[$root]) {
        $language = $PSCompletions.get_language($root)
        $PSCompletions.completions.$root = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$root/language/$language.json"))
    }

    $input_arr = [array]$input_arr
    $PSCompletions.input_arr = $input_arr

    # 使用 hooks 覆盖默认的函数，实现一些特殊的需求，比如一些补全的动态加载
    if ($PSCompletions.config.comp_config[$root].enable_hooks -eq 1) {
        . "$($PSCompletions.path.completions)/$root/hooks.ps1"
    }
    if (!$PSCompletions.completions_data[$root]) {
        $PSCompletions.completions_data.$root = getCompletions
        $PSCompletions.completions_data."$($root)_common_options" = $PSCompletions.completions_data.$root.commonOptions.$guid | ForEach-Object { $_.CompletionText }
    }
    $completions = $PSCompletions.completions_data.$root
    $filter_list = [array](filterCompletions)
    $filter_list = [array](handleCompletions $filter_list)
    if ($space_tab) {
        $filter_list = $filter_list.Where({ $_.CompletionText -notlike "-*" -or $_.CompletionText -notin $input_arr })
    }
    else {
        $filter_list = $filter_list.Where({ $_.CompletionText -like "$([WildcardPattern]::Escape($input_arr[-1]))*" })
    }

    if ($PSCompletions.config.enable_completions_sort -eq 1) {
        $path_order = "$($PSCompletions.path.order)/$root.json"
        if ($PSCompletions.order."$($root)_job") {
            if ($PSCompletions.order."$($root)_job".State -eq 'Completed') {
                $PSCompletions.order.$root = Receive-Job $PSCompletions.order."$($root)_job"
                Remove-Job $PSCompletions.order."$($root)_job"
                $PSCompletions.order.Remove("$($root)_job")
            }
        }
        else {
            if (Test-Path $path_order) {
                try {
                    $PSCompletions.order.$root = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path_order))
                }
                catch {
                    $PSCompletions.order.$root = $null
                }
            }
            else {
                $PSCompletions.order.$root = $null
            }
        }
        $order = $PSCompletions.order.$root
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

    $filter_list = [array]$filter_list

    $return = @()
    if ($space_tab) {
        foreach ($item in $filter_list) {
            if ($item -ne $null) {
                $has_alias = $false
                if ($item.alias) {
                    foreach ($a in $item.alias) {
                        if ($a -in $PSCompletions.input_arr) {
                            $has_alias = $true
                            break
                        }
                    }
                }
                if (!$has_alias) {
                    $padSymbols = foreach ($c in $item.symbols) { $PSCompletions.config.$c }
                    $padSymbols = if ($padSymbols) { "$($PSCompletions.config.between_item_and_symbol)$($padSymbols -join '')" }else { '' }
                    $return += @{
                        ListItemText   = $item.ListItemText + $padSymbols
                        CompletionText = $item.CompletionText
                        ToolTip        = $item.ToolTip
                    }
                }
            }
        }
        return $return
    }
    else {
        foreach ($item in $filter_list) {
            if ($item -ne $null) {
                $padSymbols = foreach ($c in $item.symbols) { $PSCompletions.config.$c }
                $padSymbols = if ($padSymbols) { "$($PSCompletions.config.between_item_and_symbol)$($padSymbols -join '')" }else { '' }
                $return += @{
                    ListItemText   = $item.ListItemText + $padSymbols
                    CompletionText = $item.CompletionText
                    ToolTip        = $item.ToolTip
                }
            }
        }
        return $return
    }
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

    foreach ($arr in $PSCompletions.split_array($list, [Environment]::ProcessorCount, $true)) {
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
        $content_config | ConvertTo-Json -Compress -Depth 100 | Out-File $path_config -Encoding utf8 -Force
    }
    if ($PSCompletions.config.comp_config[$completion].language) {
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
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_list {
    $PSCompletions.ensure_dir($PSCompletions.path.temp)
    if (!(Test-Path $PSCompletions.path.completions_json)) {
        @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
    }
    $current_list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list
    $isErr = $true
    foreach ($url in $PSCompletions.urls) {
        try {
            $content = (Invoke-WebRequest -Uri "$url/completions.json").Content | ConvertFrom-Json

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
            $isErr = $false
            return $remote_list
        }
        catch {
            $PSCompletions.list = $current_list
            $PSCompletions._invalid_url += "`n$url/completions.json"
        }
    }
    if ($isErr) {
        $PSCompletions._invalid_url = $PSCompletions._invalid_url | Sort-Object -Unique
        return $false
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_file {
    param(
        [string]$path, # 相对于 $baseUrl 的文件路径
        [string]$file,
        [array]$baseUrl
    )

    $isErr = $true
    $errList = @()

    for ($i = 0; $i -lt $baseUrl.Count; $i++) {
        $item = $baseUrl[$i]
        $url = $item + '/' + $path
        try {
            $PSCompletions.wc.DownloadFile($url, $file)
            $isErr = $false
            break
        }
        catch {
            $errList += @{
                url  = $url
                file = $file
                err  = $_
            }
        }
    }
    if ($isErr) {
        for ($i = 0; $i -lt $errList.Count; $i++) {
            $item = $errList[$i]
            if ($PSCompletions.info) {
                $download_info = @{
                    url  = $item.url
                    file = $item.file
                }
                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.err.download_file))
            }
            else {
                Write-Host "File ($(Split-Path $item.url -Leaf)) download failed, please check your network connection or try again later." -ForegroundColor Red
                Write-Host "File download Url: $($item.url)" -ForegroundColor Red
                Write-Host "File save path: $($item.file)" -ForegroundColor Red
                Write-Host "If you are sure that it is not a network problem, please submit an issue`n" -ForegroundColor Red
            }
            if ($i -eq $errList.Count - 1) {
                throw $item.err
            }
            else {
                Write-Host $item.err -f Red
            }
            Write-Host ''
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
    $config | ConvertTo-Json -Compress -Depth 100 | Out-File $download_info.file -Encoding utf8 -Force

    $files = @(
        @{
            Uri     = "$url/guid.txt"
            OutFile = Join-Path $completion_dir 'guid.txt'
        }
    )
    foreach ($_ in $config.language) {
        $files += @{
            Uri     = "$url/language/$_.json"
            OutFile = Join-Path $language_dir "$_.json"
        }
    }
    if ($config.hooks -ne $null) {
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
        $PSCompletions.data.alias.$completion = @()
    }

    $PSCompletions._alias_conflict = $false
    $conflict_alias_list = @()
    if ($config.alias) {
        foreach ($a in $config.alias) {
            if ($a -notin $PSCompletions.data.alias.$completion) {
                $PSCompletions.data.alias.$completion += $a
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
        if ($completion -notin $PSCompletions.data.alias.$completion) {
            $PSCompletions.data.alias.$completion += $completion
            if ($PSCompletions.data.aliasMap[$completion]) {
                $PSCompletions._alias_conflict = $true
                $conflict_alias_list += $completion
            }
            else {
                $PSCompletions.data.aliasMap.$completion = $completion
            }
            $PSCompletions._need_update_data = $true
        }
    }

    if ($PSCompletions._alias_conflict) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.err.alias_conflict))
    }

    $language = $PSCompletions.get_language($completion)
    $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$completion_dir/language/$language.json"))
    if (!$PSCompletions.completions) {
        $PSCompletions.completions = @{}
    }
    $PSCompletions.completions.$completion = $json

    if ($log) { $PSCompletions.write_with_color($PSCompletions.replace_content($done)) }

    if ($json.config) {
        if (!$PSCompletions.config.comp_config[$completion]) {
            $PSCompletions.config.comp_config.$completion = @{}
        }
        foreach ($_ in $json.config) {
            if (!($PSCompletions.config.comp_config.$completion.$($_.name))) {
                $PSCompletions.config.comp_config.$completion.$($_.name) = $_.value
                $PSCompletions._need_update_data = $true
            }
        }
    }
    if ($config.hooks -ne $null) {
        if (!$PSCompletions.config.comp_config[$completion]) {
            $PSCompletions.config.comp_config.$completion = @{}
        }
        if ($PSCompletions.config.comp_config.$completion.enable_hooks -eq $null) {
            $PSCompletions.config.comp_config.$completion.enable_hooks = [int]$config.hooks
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
    foreach ($_ in Get-ChildItem -Path $PSCompletions.path.completions -Directory) {
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
        $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($_.FullName)/language/$language.json"))
        $data.config.comp_config.$name = @{}
        foreach ($_ in $json.config) {
            $data.config.comp_config.$name.$($_.name) = $_.value
        }
        if ($config.hooks -ne $null) {
            $data.config.comp_config.$name.enable_hooks = [int]$config.hooks
        }
    }
    $data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
    $PSCompletions.data = $data
    $null = $PSCompletions.download_list()
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod init_data {
    $PSCompletions.completions = @{}
    if ((Test-Path $PSCompletions.path.data) -and !$PSCompletions.is_first_init) {
        $PSCompletions.data = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($PSCompletions.path.data))
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
            $PSCompletions.urls = @('https://abgox.github.io/PSCompletions', 'https://gitee.com/abgox/PSCompletions/raw/main', 'https://github.com/abgox/PSCompletions/raw/main')
        }
        else {
            $PSCompletions.url = 'https://github.com/abgox/PSCompletions/raw/main'
            $PSCompletions.urls = @('https://abgox.github.io/PSCompletions', 'https://github.com/abgox/PSCompletions/raw/main', 'https://gitee.com/abgox/PSCompletions/raw/main')
        }
    }

    $PSCompletions.list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list

    $PSCompletions.update = $PSCompletions.get_content($PSCompletions.path.update)
    if ('psc' -notin $PSCompletions.data.list) {
        $PSCompletions.add_completion('psc', $false)
        $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
    }
    if ($PSCompletions.completions.psc.info) {
        $PSCompletions.info = $PSCompletions.completions.psc.info
    }
    else {
        $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }
        $PSCompletions.info = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/psc/language/$language.json")).info
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

    $json = $PSCompletions.completions.$($PSCompletions.root_cmd)
    $info = $json.info

    # is_show_tip
    $enable_tip = $PSCompletions.config.comp_config.$($PSCompletions.root_cmd).enable_tip
    if ($enable_tip -ne $null) {
        $PSCompletions.menu.is_show_tip = $enable_tip -eq 1
    }
    else {
        $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip -eq 1
    }

    if ($PSCompletions.menu.is_show_tip) {
        foreach ($_ in $filter_list) {
            if ($_.ToolTip -ne $null) {
                $tip = $PSCompletions.replace_content($_.ToolTip)
            }
            else {
                $tip = ' '
            }
            $padSymbols = foreach ($c in $_.symbols) { $PSCompletions.config.$c }
            $padSymbols = if ($padSymbols) { "$($PSCompletions.config.between_item_and_symbol)$($padSymbols -join '')" }else { '' }
            [CompletionResult]::new($_.CompletionText, ($_.ListItemText + $padSymbols), 'ParameterValue', $tip)
        }
    }
    else {
        foreach ($_ in $filter_list) {
            $padSymbols = foreach ($c in $_.symbols) { $PSCompletions.config.$c }
            $padSymbols = if ($padSymbols) { "$($PSCompletions.config.between_item_and_symbol)$($padSymbols -join '')" }else { '' }
            [CompletionResult]::new($_.CompletionText, ($_.ListItemText + $padSymbols), 'ParameterValue', ' ')
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod argc_completions {
    param(
        [array]$completions, # The list of completions.
        [bool]$isShowTip = $PSCompletions.config.enable_tip_when_enhance # Set whether to display the tooltip or not.
    )

    $PSCompletions.menu.is_show_tip = $isShowTip
    foreach ($_ in $completions) {
        Register-ArgumentCompleter -Native -CommandName $_ -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            $words = @($commandAst.CommandElements | Where { $_.Extent.StartOffset -lt $cursorPosition } | ForEach-Object {
                    $word = $_.ToString()
                    if ($word.Length -gt 2) {
                        if (($word.StartsWith('"') -and $word.EndsWith('"')) -or ($word.StartsWith("'") -and $word.EndsWith("'"))) {
                            $word = $word.Substring(1, $word.Length - 2)
                        }
                    }
                    return $word
                })
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
            @((argc --argc-compgen powershell $emptyS $words) -split "`n") | ForEach-Object {
                $parts = ($_ -split "`t")

                if ($PSCompletions.menu.is_show_tip) {
                    $tip = if ($parts[3] -eq '') { ' ' }else { $parts[3] }
                    [CompletionResult]::new($parts[0], $parts[0], [CompletionResultType]::ParameterValue, $tip)
                }
                else {
                    [CompletionResult]::new($parts[0], $parts[0], [CompletionResultType]::ParameterValue, ' ')
                }
            }
        }
    }
}

if (!(Test-Path $PSCompletions.path.temp)) {
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
                        if ($_.Name -ne 'psc') {
                            Move-Item $_.FullName $PSCompletions.path.completions -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
                }

                foreach ($f in @('temp', 'completions')) {
                    Move-Item "$old_version_dir/$f" $PSCompletions.path.root -Force -ErrorAction SilentlyContinue
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
        if ($PSUICulture -eq 'zh-CN') {
            $language = 'zh-CN'
            $urls = @('https://gitee.com/abgox/PSCompletions/raw/main', 'https://github.com/abgox/PSCompletions/raw/main')
        }
        else {
            $language = 'en-US'
            $urls = @('https://github.com/abgox/PSCompletions/raw/main', 'https://gitee.com/abgox/PSCompletions/raw/main')
        }

        $PSCompletions.ensure_dir($PSCompletions.path.completions)
        $PSCompletions.ensure_dir("$($PSCompletions.path.completions)/psc")
        $PSCompletions.ensure_dir("$($PSCompletions.path.completions)/psc/language")

        $path_config = "$($PSCompletions.path.completions)/psc/config.json"

        $PSCompletions.download_file("completions/psc/config.json", $path_config, $urls)

        $config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
        $config | ConvertTo-Json -Compress -Depth 100 | Out-File $path_config -Encoding utf8 -Force

        $file_list = @('guid.txt')
        if ($config.hooks -ne $null) {
            $file_list += 'hooks.ps1'
        }
        foreach ($lang in $config.language) {
            $file_list += "language/$lang.json"
        }
        foreach ($_ in $file_list) {
            $outFile = "$($PSCompletions.path.completions)/psc/$_"
            $PSCompletions.download_file("completions/psc/$_", $outFile, $urls)
            if ($outFile -match '\.json$') {
                $PSCompletions.get_raw_content($outFile) | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 100 | Out-File $outFile -Encoding utf8 -Force
            }
        }
        $PSCompletions.info = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/psc/language/$language.json")).info
    }
    $PSCompletions.move_old_version()
    $PSCompletions.ensure_dir($PSCompletions.path.temp)
    $PSCompletions.ensure_dir($PSCompletions.path.order)
    $PSCompletions.is_init = $true
}

$PSCompletions.init_data()

if ($PSCompletions.is_init) {
    $null = $PSCompletions.download_list()
    if ($PSCompletions.is_first_init) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.init_info))
        $PScompletions.list | Out-File $PSCompletions.path.change -Encoding utf8 -Force
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.update_info))
    }
}
if (!$PSCompletions.config.enable_menu) {
    Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete
}
$PSCompletions.generate_completion()
$PSCompletions.handle_completion()

foreach ($_ in $PSCompletions.data.aliasMap.Keys) {
    if ($PSCompletions.data.aliasMap[$_] -eq 'psc') {
        Set-Alias $_ $PSCompletions.config.function_name -ErrorAction SilentlyContinue
    }
    else {
        if ($_ -ne $PSCompletions.data.aliasMap.$_) {
            Set-Alias $_ $PSCompletions.data.aliasMap.$_ -ErrorAction SilentlyContinue
        }
    }
}

if ($PSCompletions.config.enable_module_update -notin @(0, 1)) {
    $PSCompletions.version_list = $PSCompletions.config.enable_module_update, $PSCompletions.version | Sort-Object { [version] $_ } -Descending -ErrorAction SilentlyContinue
    if ($PSCompletions.version_list[0] -ne $PSCompletions.version) {
        $PSCompletions.download_file("module/CHANGELOG.json", (Join-Path $PSCompletions.path.temp 'CHANGELOG.json'), $PSCompletions.urls)

        # XXX: 这里是为了避免 CompletionPredictor 模块引起的多次确认
        if (!$PSCompletions._write_update_confirm) {
            $PSCompletions._write_update_confirm = $true
            $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update))
            while (($PSCompletions._PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode) {
                if ($PSCompletions._PressKey.ControlKeyState -notlike '*CtrlPressed*') {
                    if ($write_empty_line) { Write-Host '' }
                    if ($PSCompletions._PressKey.VirtualKeyCode -eq 13) {
                        # 13: Enter
                        $PSCompletions._cmd_list = @(
                            "Update-Module PSCompletions -RequiredVersion $($PSCompletions.version_list[0]) -Force -ErrorAction Stop",
                            "Update-PSResource PSCompletions -Version $($PSCompletions.version_list[0]) -Force -ErrorAction Stop",
                            "Scoop update pscompletions"
                        )
                        foreach ($update_cmd in $PSCompletions._cmd_list) {
                            try {
                                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.updating))
                                Invoke-Expression $update_cmd
                                break
                            }
                            catch {
                                Write-Host $_ -ForegroundColor Red
                            }
                        }
                    }
                    else {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.confirm_cancel))
                    }
                    break
                }
            }
        }
    }
    else {
        $PSCompletions.config.enable_module_update = 1
        $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
    }
}
else {
    if (!$PSCompletions._show_update_info) {
        $PSCompletions._show_update_info = $true
        if ($PSCompletions.config.enable_completions_update -eq 1) {
            if (($PSCompletions.update -or $PSCompletions.get_content($PSCompletions.path.change) -and !$PScompletions.is_init)) {
                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.update_info))
            }
        }
    }
}
$PSCompletions.is_init = $null

$PSCompletions.start_job()
