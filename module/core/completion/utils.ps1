Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_completion {
    # 获取 json 数据
    if ($PSCompletions.job.State -eq 'Completed') {
        $data = Receive-Job $PSCompletions.job
        foreach ($_ in $data.Keys) {
            $PSCompletions.data.$_ = $data.$_
        }
        Remove-Job $PSCompletions.job
        $PSCompletions.job = $null
    }
    if (!$PSCompletions.data.$root -or $PSCompletions.config.disable_cache) {
        $language = $PSCompletions.get_language($root)
        $PSCompletions.data.$root = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($root)/language/$($language).json"))
    }

    $input_arr = [array]$input_arr

    $common_options = @()
    $common_options_with_next = @()
    if ($PSCompletions.data.$root.common_options) {
        foreach ($_ in $PSCompletions.data.$root.common_options) {
            foreach ($a in $_.alias) {
                $common_options += $a
                if ($_.next) { $common_options_with_next += $a }
            }
            $common_options += $_.name
            if ($_.next) { $common_options_with_next += $_.name }
        }
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

        $tasks = @()
        if ($PSCompletions.data.$root.root) {
            $tasks += @{
                node     = $PSCompletions.data.$root.root
                isOption = $false
            }
        }
        if ($PSCompletions.data.$root.options) {
            $tasks += @{
                node     = $PSCompletions.data.$root.options
                isOption = $true
            }
        }
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
                        $data = ($data -join $separator)
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

                            $symbols = foreach ($c in $symbols) { $PSCompletions.config."symbol_$($c)" }
                            $symbols = $symbols -join ''
                            $padSymbols = if ($symbols) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbols)" }else { '' }

                            $completions.Add(@{
                                    name           = $pre + $pad + $_.name
                                    ListItemText   = "$($_.name)$($padSymbols)"
                                    CompletionText = $_.name
                                    ToolTip        = $_.tip
                                })
                            if ($_.alias) {
                                if ($isOption) {
                                    foreach ($a in $_.alias) {
                                        $completions.Add(@{
                                                name           = $pre + $pad + $a
                                                ListItemText   = "$($a)$($padSymbols)"
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
                                        if (!($_alias_map[$index])) { $_alias_map[$index] = @() }
                                        $_alias_map[$index] += @{
                                            name  = $_.name
                                            alias = $a
                                        }
                                        $completions.Add(@{
                                                name           = $pre + $pad + $a
                                                ListItemText   = "$($a)$($padSymbols)"
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
                if ($alias_map[$a]) {
                    $alias_map[$a] += $result.alias_map[$a]
                }
                else {
                    $alias_map[$a] = $result.alias_map[$a]
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
            if ($alias_map[$i]) {
                foreach ($obj in $alias_map[$i]) {
                    if ($obj.alias -eq $filter_input_arr[$i]) {
                        $alias_input_arr[$i] = $obj.name
                        break
                    }
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
        if ($PSCompletions.data.$root.common_options) {
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

                $symbols = foreach ($c in $symbols) { $PSCompletions.config."symbol_$($c)" }
                $symbols = $symbols -join ''
                if ($symbols) {
                    "$($PSCompletions.config.menu_between_item_and_symbol)$($symbols)"
                }
                else {
                    ''
                }
            }
            if ($space_tab) {
                if ($input_arr[-1] -in $common_options_with_next -and ($input_arr -notlike "*$($input_arr[-1])*$($input_arr[-1])*" -or $input_arr -like "*$($input_arr[-1])")) {
                    $filter_list = @()
                    $filter = $PSCompletions.data.$root.common_options.Where({ $_.name -eq $input_arr[-1] -or $_.alias -contains $input_arr[-1] })
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
                foreach ($_ in $PSCompletions.data.$root.common_options) {
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
                                $name_with_symbol = "$($a)$(Get-PadSymbols)"
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
                    $filter = $PSCompletions.data.$root.common_options.Where({ $_.name -eq $input_arr[-2] -or $_.alias -contains $input_arr[-2] })
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
                foreach ($_ in $PSCompletions.data.$root.common_options) {
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
                            $name_with_symbol = "$($a)$(Get-PadSymbols)"
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

    if ($PSCompletions.config.comp_config.$root.disable_hooks -ne 1) {
        # 使用 hooks 覆盖默认的函数，实现在一些特殊的需求，比如一些补全的动态加载
        $path_hook = "$($PSCompletions.path.completions)/$($root)/hooks.ps1"
        if (Test-Path $path_hook) { . $path_hook }
    }
    $completions = getCompletions
    $completions = handleCompletions $completions
    $filter_list = filterCompletions $completions $root

    # 排序
    if ($PSCompletions.config.menu_completions_sort) {
        $path_order = "$($PSCompletions.path.completions)/$($root)/order.json"
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
