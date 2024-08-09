Add-Member -InputObject $PSCompletions -MemberType ScriptMethod generate_completion {
    if ($this.config.menu_enhance -and $this.config.menu_enable) {
        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
            Set-PSReadLineKeyHandler -Key $this.config.menu_trigger_key -ScriptBlock {
                $buffer = ''
                $cursorPosition = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursorPosition)
                if (!$cursorPosition) {
                    return
                }

                # 是否是按下空格键触发的补全
                $space_tab = if ($buffer[-1] -eq " ") { 1 }else { 0 }

                # Windows PowerShell 5.x
                if ($PSEdition -ne "Core") {
                    $PSCompletions.config.menu_line_horizontal = "-"
                    $PSCompletions.config.menu_line_vertical = "|"
                    $PSCompletions.config.menu_line_top_left = "+"
                    $PSCompletions.config.menu_line_bottom_left = "+"
                    $PSCompletions.config.menu_line_top_right = "+"
                    $PSCompletions.config.menu_line_bottom_right = "+"
                }

                # 使用正则表达式进行分割，将命令行中的每个参数分割出来，形成一个数组， 引号包裹的内容会被当作一个参数，且数组会包含 "--"
                $input_arr = [System.Collections.Generic.List[string]]@()
                $matches = [regex]::Matches($buffer, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                foreach ($match in $matches) { $input_arr.Add($match.Value) }

                # 触发补全的值，此值可能是别名或命令名
                $alias = $input_arr[0]

                # 原始的命令名，也是 completions 目录下的命令目录名
                if ($PSCompletions.alias.$alias -and $input_arr[-1] -notmatch "^(?:\.\.?|~)?(?:[/\\]).*") {
                    if ($buffer -eq $alias) { return }
                    $PSCompletions.current_cmd = $root = $PSCompletions.alias.$alias

                    $input_arr.RemoveAt(0)

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

                    $common_options = [System.Collections.Generic.List[string]]@()
                    $common_options_with_next = [System.Collections.Generic.List[string]]@()
                    if ($PSCompletions.data.$root.common_options) {
                        foreach ($_ in $PSCompletions.data.$root.common_options) {
                            foreach ($a in $_.alias) {
                                $common_options.Add($a)
                                if ($_.next) { $common_options_with_next.Add($a) }
                            }
                            $common_options.Add($_.name)
                            if ($_.next) { $common_options_with_next.Add($_.name) }
                        }
                    }
                    $WriteSpaceTab = [System.Collections.Generic.List[string]]@()
                    $WriteSpaceTab.AddRange($common_options_with_next)

                    $WriteSpaceTab_and_SpaceTab = [System.Collections.Generic.List[string]]@()

                    # 存储别名的映射，用于在过滤时允许别名
                    $alias_map = @{}

                    function getCompletions {
                        $completions = [System.Collections.Generic.List[System.Object]]@()

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
                                        param($node, $pre, $isOption)
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
                                                        if (!($alias_map[$index])) { $alias_map[$index] = @() }
                                                        $alias_map[$index] += @{
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
                                            if ($symbols) {
                                                if ('WriteSpaceTab' -in $symbols) {
                                                    $WriteSpaceTab.Add($_.name)
                                                    if ($_.alias) {
                                                        foreach ($a in $_.alias) { $WriteSpaceTab.Add($a) }
                                                    }
                                                    if ('SpaceTab' -in $symbols) {
                                                        $WriteSpaceTab_and_SpaceTab.Add($_.name)
                                                        if ($_.alias) {
                                                            foreach ($a in $_.alias) { $WriteSpaceTab_and_SpaceTab.Add($a) }
                                                        }
                                                    }
                                                }
                                            }
                                            if ($_.next) { parseCompletions $_.next ($pre + $pad + $_.name) }
                                            if ($_.options) { parseCompletions $_.options ($pre + $pad + $_.name) -isOption }
                                        }
                                    }
                                    parseCompletions $obj.node '' $obj.isOption
                                    return $completions
                                }).AddArgument($task).AddArgument($PSCompletions)
                            $runspace.RunspacePool = $runspacePool
                            $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
                        }

                        # 等待所有任务完成
                        foreach ($rs in $runspaces) {
                            $result = $rs.Runspace.EndInvoke($rs.Job)
                            $rs.Runspace.Dispose()
                            $completions.AddRange($result)
                        }
                        return $completions
                    }
                    function handleCompletions {
                        param($completions)
                        return $completions
                    }
                    function filterCompletions {
                        param($completions, $root)

                        # 当这个 options 是 WriteSpaceTab 时，将下一个值直接过滤掉
                        $need_skip = $false

                        $filter_input_arr = [System.Collections.Generic.List[string]]@()
                        foreach ($_ in $input_arr) {
                            if ($_ -like '-*' -or $need_skip) {
                                if ($need_skip) { $need_skip = $false }
                                if ($_ -in $WriteSpaceTab) {
                                    if ($input_arr[-1 - !$space_tab] -eq $_ -and $_ -in $WriteSpaceTab_and_SpaceTab) {
                                        $need_add = $true
                                    }
                                    else {
                                        $need_skip = $true
                                    }
                                }
                            }
                            else { $need_add = $true }
                            if ($need_add -and $_ -notin $common_options) {
                                $filter_input_arr.Add($_)
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

                        $filter_list = [System.Collections.Generic.List[System.Object]]@()

                        $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
                        $runspacePool.Open()
                        $runspaces = @()

                        foreach ($completions in $PSCompletions.split_array($completions, [Environment]::ProcessorCount, $true)) {
                            $runspace = [powershell]::Create().AddScript({
                                    param($completions, $input_arr, $filter_input_arr, $match, $alias_input_arr, $space_tab)
                                    foreach ($completion in $completions) {
                                        $matches = [regex]::Matches($completion.name, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                                        $cmd = [System.Collections.Generic.List[string]]@()
                                        foreach ($m in $matches) { $cmd.Add($m.Value) }
                                        <#
                                            判断选项是否使用过了，如果使用过了，$no_used 为 $true
                                            这里的判断对于 --file="abc" 这样的命令无法使用，因为这里和用户输入的 "abc"是连着的
                                        #>
                                        $no_used = if ($cmd[-1] -like '-*') {
                                            $cmd[-1] -notin $input_arr
                                        }
                                        else { $true }


                                        $isLike = ($completion.name -like ([WildcardPattern]::Escape($filter_input_arr -join ' ') + $match)) -or ($completion.name -like ([WildcardPattern]::Escape($alias_input_arr -join ' ') + $match))
                                        if ($no_used -and $cmd.Count -eq ($filter_input_arr.Count + $space_tab) -and $isLike) {
                                            $completion
                                        }
                                    }
                                }).AddArgument($completions).AddArgument($input_arr).AddArgument($filter_input_arr).AddArgument($match).AddArgument($alias_input_arr).AddArgument($space_tab)


                            $runspace.RunspacePool = $runspacePool
                            $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
                        }

                        # 等待所有任务完成
                        foreach ($rs in $runspaces) {
                            $result = $rs.Runspace.EndInvoke($rs.Job)
                            $rs.Runspace.Dispose()
                            if ($result) {
                                $filter_list.AddRange($result)
                            }
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
                                    $filter_list.Clear()
                                    $PSCompletions.data.$root.common_options | Where-Object {
                                        $_.name -eq $input_arr[-1] -or $_.alias -contains $input_arr[-1]
                                    } | ForEach-Object {
                                        foreach ($n in $_.next) {
                                            $filter_list.Add(@{
                                                    ListItemText   = $n.name
                                                    CompletionText = $n.name
                                                    ToolTip        = $n.tip
                                                })
                                        }
                                    }
                                }
                                foreach ($_ in $PSCompletions.data.$root.common_options) {
                                    if ($_.name -notin $input_arr) {
                                        $isExist = $false
                                        $temp_list = [System.Collections.Generic.List[System.Object]]@()

                                        $temp_list.Add(@{
                                                ListItemText   = "$($_.name)$(Get-PadSymbols)"
                                                CompletionText = $_.name
                                                ToolTip        = $_.tip
                                            })

                                        foreach ($a in $_.alias) {
                                            if ($a -notin $input_arr) {
                                                $temp_list.Add(@{
                                                        ListItemText   = "$($a)$(Get-PadSymbols)"
                                                        CompletionText = $a
                                                        ToolTip        = $_.tip
                                                    })
                                            }
                                            else {
                                                $temp_list.Clear()
                                                break
                                            }
                                        }
                                        $filter_list.AddRange($temp_list)
                                    }
                                }
                            }
                            else {
                                if ($input_arr[-2] -in $common_options_with_next -and $input_arr -notlike "*$($input_arr[-2])*$($input_arr[-2])*") {
                                    $filter_list.Clear()
                                    $PSCompletions.data.$root.common_options | Where-Object {
                                        $_.name -eq $input_arr[-2] -or $_.alias -contains $input_arr[-2]
                                    } | ForEach-Object {
                                        foreach ($n in $_.next) {
                                            if ($n.name -like "$($input_arr[-1])*") {
                                                $filter_list.Add(@{
                                                        ListItemText   = $n.name
                                                        CompletionText = $n.name
                                                        ToolTip        = $n.tip
                                                    })
                                            }
                                        }
                                    }
                                }
                                foreach ($_ in $PSCompletions.data.$root.common_options) {
                                    if ($_.name -notin $input_arr -and $_.name -like "$($input_arr[-1])*") {
                                        $filter_list.Add(@{
                                                ListItemText   = "$($_.name)$(Get-PadSymbols)"
                                                CompletionText = $_.name
                                                ToolTip        = $_.tip
                                            })
                                    }
                                    foreach ($a in $_.alias) {
                                        if ($a -notin $input_arr -and $a -like "$($input_arr[-1])*") {
                                            $filter_list.Add(@{
                                                    ListItemText   = "$($a)$(Get-PadSymbols)"
                                                    CompletionText = $a
                                                    ToolTip        = $_.tip
                                                })
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
                    $result = $PSCompletions.menu.show_module_menu($filter_list)
                    if ($result) {
                        if ($space_tab) {
                            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result)
                        }
                        else {
                            $input_arr.RemoveAt($input_arr.Count - 1)
                            if ($input_arr.Count -eq 0) {
                                $result = "$alias $result"
                            }
                            else {
                                $result = "$alias $($input_arr -join ' ') $result"
                            }
                            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $buffer.Length, $result)
                        }
                    }
                }
                else {
                    try {
                        $completion = TabExpansion2 $buffer $cursorPosition
                    }
                    catch {
                        return
                    }
                    if (!$completion.CompletionMatches) {
                        return
                    }
                    $result = $PSCompletions.menu.show_module_menu($completion.CompletionMatches, $true)
                    # apply the completion
                    if ($result) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($completion.ReplacementIndex, $completion.ReplacementLength, $result)
                    }
                }
                $PSCompletions.current_cmd = $null
            }
        }
    }
    else {
        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
            foreach ($_ in $this.alias.keys) {
                Register-ArgumentCompleter -CommandName $_ -ScriptBlock {
                    param($word_to_complete, $command_ast, $cursor_position)

                    # 使用正则表达式进行分割，将命令行中的每个参数分割出来，形成一个数组， 引号包裹的内容会被当作一个参数，且数组会包含 "--"
                    $input_arr = [System.Collections.Generic.List[string]]@()
                    $matches = [regex]::Matches($command_ast.CommandElements, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                    foreach ($match in $matches) { $input_arr.Add($match.Value) }

                    # 触发补全的值，此值可能是别名或命令名
                    $alias = $input_arr[0]

                    # 原始的命令名，也是 completions 目录下的命令目录名
                    $PSCompletions.current_cmd = $root = $PSCompletions.alias.$alias

                    $input_arr.RemoveAt(0)

                    # 是否是按下空格键触发的补全
                    $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }

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

                    $common_options = [System.Collections.Generic.List[string]]@()
                    $common_options_with_next = [System.Collections.Generic.List[string]]@()
                    if ($PSCompletions.data.$root.common_options) {
                        foreach ($_ in $PSCompletions.data.$root.common_options) {
                            foreach ($a in $_.alias) {
                                $common_options.Add($a)
                                if ($_.next) { $common_options_with_next.Add($a) }
                            }
                            $common_options.Add($_.name)
                            if ($_.next) { $common_options_with_next.Add($_.name) }
                        }
                    }
                    $WriteSpaceTab = [System.Collections.Generic.List[string]]@()
                    $WriteSpaceTab.AddRange($common_options_with_next)

                    $WriteSpaceTab_and_SpaceTab = [System.Collections.Generic.List[string]]@()

                    # 存储别名的映射，用于在过滤时允许别名
                    $alias_map = @{}

                    function getCompletions {
                        $completions = [System.Collections.Generic.List[System.Object]]@()

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
                                        param($node, $pre, $isOption)
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
                                                        if (!($alias_map[$index])) { $alias_map[$index] = @() }
                                                        $alias_map[$index] += @{
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
                                            if ($symbols) {
                                                if ('WriteSpaceTab' -in $symbols) {
                                                    $WriteSpaceTab.Add($_.name)
                                                    if ($_.alias) {
                                                        foreach ($a in $_.alias) { $WriteSpaceTab.Add($a) }
                                                    }
                                                    if ('SpaceTab' -in $symbols) {
                                                        $WriteSpaceTab_and_SpaceTab.Add($_.name)
                                                        if ($_.alias) {
                                                            foreach ($a in $_.alias) { $WriteSpaceTab_and_SpaceTab.Add($a) }
                                                        }
                                                    }
                                                }
                                            }
                                            if ($_.next) { parseCompletions $_.next ($pre + $pad + $_.name) }
                                            if ($_.options) { parseCompletions $_.options ($pre + $pad + $_.name) -isOption }
                                        }
                                    }
                                    parseCompletions $obj.node '' $obj.isOption
                                    return $completions
                                }).AddArgument($task).AddArgument($PSCompletions)
                            $runspace.RunspacePool = $runspacePool
                            $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
                        }

                        # 等待所有任务完成
                        foreach ($rs in $runspaces) {
                            $result = $rs.Runspace.EndInvoke($rs.Job)
                            $rs.Runspace.Dispose()
                            $completions.AddRange($result)
                        }
                        return $completions
                    }
                    function handleCompletions {
                        param($completions)
                        return $completions
                    }
                    function filterCompletions {
                        param($completions, $root)

                        # 当这个 options 是 WriteSpaceTab 时，将下一个值直接过滤掉
                        $need_skip = $false

                        $filter_input_arr = [System.Collections.Generic.List[string]]@()
                        foreach ($_ in $input_arr) {
                            if ($_ -like '-*' -or $need_skip) {
                                if ($need_skip) { $need_skip = $false }
                                if ($_ -in $WriteSpaceTab) {
                                    if ($input_arr[-1 - !$space_tab] -eq $_ -and $_ -in $WriteSpaceTab_and_SpaceTab) {
                                        $need_add = $true
                                    }
                                    else {
                                        $need_skip = $true
                                    }
                                }
                            }
                            else { $need_add = $true }
                            if ($need_add -and $_ -notin $common_options) {
                                $filter_input_arr.Add($_)
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

                        $filter_list = [System.Collections.Generic.List[System.Object]]@()

                        $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
                        $runspacePool.Open()
                        $runspaces = @()

                        foreach ($completions in $PSCompletions.split_array($completions, [Environment]::ProcessorCount, $true)) {
                            $runspace = [powershell]::Create().AddScript({
                                    param($completions, $input_arr, $filter_input_arr, $match, $alias_input_arr, $space_tab)
                                    foreach ($completion in $completions) {
                                        $matches = [regex]::Matches($completion.name, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                                        $cmd = [System.Collections.Generic.List[string]]@()
                                        foreach ($m in $matches) { $cmd.Add($m.Value) }
                                        <#
                                                判断选项是否使用过了，如果使用过了，$no_used 为 $true
                                                这里的判断对于 --file="abc" 这样的命令无法使用，因为这里和用户输入的 "abc"是连着的
                                            #>
                                        $no_used = if ($cmd[-1] -like '-*') {
                                            $cmd[-1] -notin $input_arr
                                        }
                                        else { $true }

                                        $isLike = ($completion.name -like ([WildcardPattern]::Escape($filter_input_arr -join ' ') + $match)) -or ($completion.name -like ([WildcardPattern]::Escape($alias_input_arr -join ' ') + $match))
                                        if ($no_used -and $cmd.Count -eq ($filter_input_arr.Count + $space_tab) -and $isLike) {
                                            $completion
                                        }
                                    }
                                }).AddArgument($completions).AddArgument($input_arr).AddArgument($filter_input_arr).AddArgument($match).AddArgument($alias_input_arr).AddArgument($space_tab)


                            $runspace.RunspacePool = $runspacePool
                            $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
                        }

                        # 等待所有任务完成
                        foreach ($rs in $runspaces) {
                            $result = $rs.Runspace.EndInvoke($rs.Job)
                            $rs.Runspace.Dispose()
                            if ($result) {
                                $filter_list.AddRange($result)
                            }
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
                                    $filter_list.Clear()
                                    $PSCompletions.data.$root.common_options | Where-Object {
                                        $_.name -eq $input_arr[-1] -or $_.alias -contains $input_arr[-1]
                                    } | ForEach-Object {
                                        foreach ($n in $_.next) {
                                            $filter_list.Add(@{
                                                    ListItemText   = $n.name
                                                    CompletionText = $n.name
                                                    ToolTip        = $n.tip
                                                })
                                        }
                                    }
                                }
                                foreach ($_ in $PSCompletions.data.$root.common_options) {
                                    if ($_.name -notin $input_arr) {
                                        $isExist = $false
                                        $temp_list = [System.Collections.Generic.List[System.Object]]@()

                                        $temp_list.Add(@{
                                                ListItemText   = "$($_.name)$(Get-PadSymbols)"
                                                CompletionText = $_.name
                                                ToolTip        = $_.tip
                                            })

                                        foreach ($a in $_.alias) {
                                            if ($a -notin $input_arr) {
                                                $temp_list.Add(@{
                                                        ListItemText   = "$($a)$(Get-PadSymbols)"
                                                        CompletionText = $a
                                                        ToolTip        = $_.tip
                                                    })
                                            }
                                            else {
                                                $temp_list.Clear()
                                                break
                                            }
                                        }
                                        $filter_list.AddRange($temp_list)
                                    }
                                }
                            }
                            else {
                                if ($input_arr[-2] -in $common_options_with_next -and $input_arr -notlike "*$($input_arr[-2])*$($input_arr[-2])*") {
                                    $filter_list.Clear()
                                    $PSCompletions.data.$root.common_options | Where-Object {
                                        $_.name -eq $input_arr[-2] -or $_.alias -contains $input_arr[-2]
                                    } | ForEach-Object {
                                        foreach ($n in $_.next) {
                                            if ($n.name -like "$($input_arr[-1])*") {
                                                $filter_list.Add(@{
                                                        ListItemText   = $n.name
                                                        CompletionText = $n.name
                                                        ToolTip        = $n.tip
                                                    })
                                            }
                                        }
                                    }
                                }
                                foreach ($_ in $PSCompletions.data.$root.common_options) {
                                    if ($_.name -notin $input_arr -and $_.name -like "$($input_arr[-1])*") {
                                        $filter_list.Add(@{
                                                ListItemText   = "$($_.name)$(Get-PadSymbols)"
                                                CompletionText = $_.name
                                                ToolTip        = $_.tip
                                            })
                                    }
                                    foreach ($a in $_.alias) {
                                        if ($a -notin $input_arr -and $a -like "$($input_arr[-1])*") {
                                            $filter_list.Add(@{
                                                    ListItemText   = "$($a)$(Get-PadSymbols)"
                                                    CompletionText = $a
                                                    ToolTip        = $_.tip
                                                })
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
                    if ($PSCompletions.config.menu_enable) {
                        # Windows PowerShell 5.x
                        if ($PSEdition -ne "Core") {
                            $PSCompletions.config.menu_line_horizontal = "-"
                            $PSCompletions.config.menu_line_vertical = "|"
                            $PSCompletions.config.menu_line_top_left = "+"
                            $PSCompletions.config.menu_line_bottom_left = "+"
                            $PSCompletions.config.menu_line_top_right = "+"
                            $PSCompletions.config.menu_line_bottom_right = "+"
                        }
                        $PSCompletions.menu.show_module_menu($filter_list)
                    }
                    else {
                        $PSCompletions.menu.show_powershell_menu($filter_list)
                    }
                    $PSCompletions.current_cmd = $null
                }
            }
        }
    }
}
