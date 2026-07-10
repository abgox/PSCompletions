using namespace System.Management.Automation

Microsoft.PowerShell.Core\Set-StrictMode -Off

if ($PSCompletions.guid) { return }

$_ = $PSScriptRoot
New-Variable -Name PSCompletions -Option Constant -Value @{
    version                 = '6.7.0'
    path                    = @{
        root             = $_
        completions      = "$_\completions"
        core             = "$_\core"
        data             = "$_\data.json"
        temp             = "$_\temp"
        order            = "$_\temp\order"
        completions_json = "$_\temp\completions.json"
        update           = "$_\temp\update.txt"
        change           = "$_\temp\change.txt"
        last_update      = "$_\temp\last-update.txt"
        module_update    = "$_\temp\module-update.txt"
    }
    order                   = [ordered]@{}
    cmd                     = ''
    completions_data        = @{}
    guid                    = '00929632-527d-4dab-a5b3-21197faccd05'
    language                = $PSUICulture
    separator               = [System.IO.Path]::DirectorySeparatorChar
    replace_pattern         = [regex]::new('(?s)\{\{(.*?(\})*)(?=\}\})\}\}', [System.Text.RegularExpressions.RegexOptions]::Compiled)
    input_pattern           = [regex]::new("(?:`"[^`"]*`"|'[^']*'|\S)+", [System.Text.RegularExpressions.RegexOptions]::Compiled)
    menu                    = @{
        encoding                      = [System.Text.Encoding]::GetEncoding(0)
        # Set-PSReadLineKeyHandler -Key <Key> -ScriptBlock $PSCompletions.menu.module_completion_menu_script
        module_completion_menu_script = {
            try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

            $buffer = ''
            $cursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)
            if (-not $buffer) { return }

            $PSCompletions.buffer = $buffer
            $PSCompletions.buffer_after_cursor = $buffer.Substring($cursor)
            $buffer = $PSCompletions.buffer_before_cursor = $buffer.Substring(0, $cursor)
            $isSpaceTab = $buffer[-1] -eq ' '
            $inputs = @()
            $matches = [regex]::Matches($buffer, $PSCompletions.input_pattern)
            foreach ($match in $matches) { $inputs += $match.Value }

            if (!$inputs) { return }

            $PSCompletions.inputs = $inputs

            function check_confirm_limit {
                param([array]$list)
                if ($PSCompletions.config.completions_confirm_limit -gt 0 -and $list.Count -gt $PSCompletions.config.completions_confirm_limit) {
                    $count = $list.Count
                    $tip = $PSCompletions.replace_content($PSCompletions.info.module.too_many_completions.tip)
                    $_filter_list = foreach ($t in $PSCompletions.info.module.too_many_completions.text) {
                        $text = $PSCompletions.replace_content($t)
                        @{ CompletionText = $text; ListItemText = $text; ToolTip = $tip }
                    }
                    $result = $PSCompletions.menu.show_module_menu($_filter_list)
                    if (!$result) { return $null }
                }
                $list
            }

            $PSCompletions.alias = $alias = $inputs[0]
            $PSCompletions.menu.by_TabExpansion2 = $false

            if ($null -ne $PSCompletions.data.aliasMap[$alias] -and ($isSpaceTab -or ($inputs.Count -gt 1 -and $inputs[-1] -notmatch '^[''"]?(?:[A-Za-z]:[/\\]|(?:\.\.?|~)?[/\\]).*'))) {
                $PSCompletions.cmd = $cmd = $PSCompletions.data.aliasMap[$alias]
                $filter_list = $PSCompletions.get_completion($cmd, $inputs)

                $filter_list = check_confirm_limit $filter_list
                if ($null -eq $filter_list) { return '' }
                $result = $PSCompletions.menu.show_module_menu($filter_list)
                if ($result) {
                    if ($isSpaceTab) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result)
                    }
                    else {
                        $middleArgs = if ($inputs.Count -le 2) { , @() } else { $inputs[1..($inputs.Count - 2)] }
                        $result = if ($middleArgs.Count -eq 0) { "$alias $result" }else { "$alias $($middleArgs -join ' ') $result" }
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $buffer.Length, $result)
                    }
                }
            }
            else {
                try {
                    $completion = TabExpansion2 $buffer $cursor
                }
                catch {
                    return
                }
                $filter_list = $completion.CompletionMatches
                if (!$filter_list) { return }

                $filter_list = check_confirm_limit $filter_list
                if ($null -eq $filter_list) { return '' }

                $cmd = $inputs[0]
                if (-not [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($cmd)) {
                    if ($cmd -eq 'PSCompletions') {
                        $cmds = Get-Command
                        $has_command = foreach ($c in $cmds) { if ($c.Name -eq $cmd) { $c; break } }
                    }
                    else {
                        foreach ($c in $PSCompletions.data.alias.$cmd) {
                            $has_command = Get-Command $c -ErrorAction Ignore
                            if ($has_command) {
                                break
                            }
                        }
                    }
                    if ($PSCompletions.config.enable_completions_sort -and $has_command) {
                        $path_order = "$($PSCompletions.path.order)/$cmd.json"
                        if ($PSCompletions.order."$($cmd)_job") {
                            if ($PSCompletions.order."$($cmd)_job".State -eq 'Completed') {
                                $PSCompletions.order[$cmd] = Receive-Job $PSCompletions.order."$($cmd)_job"
                                Remove-Job $PSCompletions.order."$($cmd)_job"
                                $PSCompletions.order.Remove("$($cmd)_job")
                            }
                        }
                        else {
                            if (Test-Path $path_order) {
                                try {
                                    $PSCompletions.order[$cmd] = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($path_order))
                                }
                                catch {
                                    $PSCompletions.order[$cmd] = $null
                                }
                            }
                            else {
                                $PSCompletions.order[$cmd] = $null
                            }
                        }
                        $order = $PSCompletions.order[$cmd]
                        if ($order) {
                            $PSCompletions.sort_counter = 0
                            $filter_list = $filter_list | Sort-Object {
                                $PSCompletions.sort_counter --
                                $o = $order[$_.CompletionText]
                                if ($o) { $o }
                                else {
                                    $o = $order[$_.CompletionText + $PSCompletions.separator]
                                    if ($o) { $o }else { $PSCompletions.sort_counter }
                                }
                            } -Descending -CaseSensitive
                        }
                        $PSCompletions.order_job((Get-PSReadLineOption).HistorySavePath, $cmd, $path_order)
                    }
                }
                $PSCompletions.menu.by_TabExpansion2 = $true
                $result = $PSCompletions.menu.show_module_menu($filter_list)
                if ($result) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($completion.ReplacementIndex, $completion.ReplacementLength, $result)
                }
            }
        }
        const                         = @{
            symbol_item = @('SpaceTab', 'WriteSpaceTab', 'OptionTab')
            line_item   = @('horizontal', 'vertical', 'top_left', 'bottom_left', 'top_right', 'bottom_right')
            color_item  = @('item_color', 'filter_color', 'border_color', 'status_color', 'tip_color', 'selected_color', 'selected_bgcolor')
            color_value = @('White', 'Black', 'Gray', 'DarkGray', 'Red', 'DarkRed', 'Green', 'DarkGreen', 'Blue', 'DarkBlue', 'Cyan', 'DarkCyan', 'Yellow', 'DarkYellow', 'Magenta', 'DarkMagenta')
            config_item = @(
                'trigger_key', 'between_item_and_symbol', 'status_symbol', 'filter_symbol', 'completion_suffix', 'enable_menu', 'enable_menu_enhance', 'enable_menu_show_below', 'enable_tip', 'enable_hooks_tip', 'enable_tip_when_enhance', 'enable_completions_sort', 'enable_tip_follow_cursor', 'enable_list_follow_cursor', 'enable_path_with_trailing_separator', 'enable_list_loop', 'enable_enter_when_single', 'enable_list_full_width', 'enable_filter_subsequence_match', 'list_min_width', 'list_max_count_when_above', 'list_max_count_when_below', 'height_from_menu_bottom_to_cursor_when_above', 'height_from_menu_top_to_cursor_when_below', 'completions_confirm_limit', 'enter_when_no_match_after'
            )
        }
    }
    default_config          = [ordered]@{
        # config
        url                                          = ''
        language                                     = $PSUICulture
        enable_auto_alias_setup                      = 1
        enable_cache                                 = 1

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
        enable_menu_show_below                       = 0
        enable_enter_when_single                     = 0
        enable_list_loop                             = 1
        enable_list_full_width                       = 1
        enable_list_follow_cursor                    = 1
        enable_filter_subsequence_match              = 0

        enter_when_no_match_after                    = 0

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
    default_completion_item = @('language', 'enable_tip', 'enable_hooks_tip')
    config_item             = @('url', 'language', 'enable_auto_alias_setup', 'enable_cache')
}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod return_completion {
    param([string]$name, $tip = ' ', [array]$symbols)
    if ($PSCompletions.config.comp_config[$PSCompletions.cmd].enable_hooks_tip -eq 0) {
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
    param([string]$cmd, [array]$inputs)
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

    if ($null -eq $cmd) { return }

    function new_node {
        param([switch]$isOption)
        @{
            Name          = $null
            Alias         = @()
            Tip           = $null
            Repeat        = 0
            IsOption      = $isOption.IsPresent
            HasNextDef    = $false
            HasOptionDef  = $false
            NextIsArray   = $false
            OptionIsArray = $false
            Next          = [System.Collections.Hashtable]::New([System.StringComparer]::OrdinalIgnoreCase)
            Options       = [System.Collections.Hashtable]::New([System.StringComparer]::OrdinalIgnoreCase)
            NextItems     = [System.Collections.Generic.List[object]]::new()
            OptionItems   = [System.Collections.Generic.List[object]]::new()
            Parent        = $null
        }
    }
    function node_all_names {
        param($node)
        @($node.Name) + @($node.Alias)
    }
    function node_symbols {
        param($node)
        $symbols = @()
        if ($node.IsOption) {
            if (-not $node.HasNextDef -and -not $node.HasOptionDef) {
                $symbols += 'OptionTab'
            }
            else {
                $symbols += 'WriteSpaceTab'
                if ($node.NextIsArray -or $node.OptionIsArray) { $symbols += 'SpaceTab' }
            }
        }
        else {
            if ($node.NextIsArray -or $node.OptionIsArray) { $symbols += 'SpaceTab' }
        }
        $symbols
    }
    function node_takes_free_input {
        param($node)
        $node.IsOption -and ($node.HasNextDef -or $node.HasOptionDef) -and -not ($node.NextIsArray -or $node.OptionIsArray)
    }
    function node_has_candidates_after {
        param($node)
        $node.NextIsArray -or $node.OptionIsArray
    }
    function add_to_bucket {
        param($dict, $items, $node)
        foreach ($key in (node_all_names $node)) {
            if ($null -eq $key) { continue }

            $dict[$key] = $node
        }
        $items.Add($node)
    }
    function build_node {
        param($rawCmd, [switch]$isOption, $parent)

        $node = new_node -isOption:$isOption
        $node.Parent = $parent
        $node.Name = $rawCmd.name
        $node.Alias = @($rawCmd.alias | Where-Object { $_ -is [string] })
        $node.Tip = $rawCmd.tip
        $node.Repeat = if ($null -eq $rawCmd.repeat) { 0 } else { [int]$rawCmd.repeat }
        $node.HasNextDef = $null -ne $rawCmd.next
        $node.HasOptionDef = $null -ne $rawCmd.option
        $node.NextIsArray = $rawCmd.next -is [array]
        $node.OptionIsArray = $rawCmd.option -is [array]
        if ($node.NextIsArray) {
            foreach ($childRaw in $rawCmd.next) {
                $child = build_node $childRaw -parent $node
                add_to_bucket $node.Next $node.NextItems $child
            }
        }
        if ($node.OptionIsArray) {
            foreach ($childRaw in $rawCmd.option) {
                $child = build_node $childRaw -isOption -parent $node
                add_to_bucket $node.Options $node.OptionItems $child
            }
        }
        $node
    }
    function build_tree {
        param($languageJson)

        $tree = @{
            Root              = new_node
            RootOptions       = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
            RootOptionItems   = [System.Collections.Generic.List[object]]::new()
            CommonOptions     = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
            CommonOptionItems = [System.Collections.Generic.List[object]]::new()
        }
        if ($languageJson.root) {
            foreach ($cmdRaw in $languageJson.root) {
                $node = build_node $cmdRaw -parent $tree.Root
                add_to_bucket $tree.Root.Next $tree.Root.NextItems $node
            }
            $tree.Root.HasNextDef = $true
            $tree.Root.NextIsArray = $true
        }
        if ($languageJson.option) {
            foreach ($cmdRaw in $languageJson.option) {
                $node = build_node $cmdRaw -isOption -parent $tree.Root
                add_to_bucket $tree.RootOptions $tree.RootOptionItems $node
            }
        }
        if ($languageJson.common_option) {
            foreach ($cmdRaw in $languageJson.common_option) {
                $node = build_node $cmdRaw -isOption -parent $tree.Root
                add_to_bucket $tree.CommonOptions $tree.CommonOptionItems $node
            }
        }
        $tree
    }
    function expand_node_to_items {
        param($node)
        $symbols = node_symbols $node
        $names = node_all_names $node
        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($n in $names) {
            $result.Add(@{
                    CompletionText = $n
                    ListItemText   = $n
                    ToolTip        = $node.Tip
                    symbols        = $symbols
                    alias          = $names
                    repeat         = $node.Repeat
                })
        }
        $result
    }
    function match_tree {
        param($tree, [array]$argTokens, [bool]$treatLastAsComplete)

        function find_option_node {
            param($ctx, $tree, $text)
            if ($ctx.Options.ContainsKey($text)) { return $ctx.Options[$text] }
            $p = $ctx.Parent
            while ($p) {
                if ($p.Options.ContainsKey($text)) { return $p.Options[$text] }
                $p = $p.Parent
            }
            if ($tree.RootOptions.ContainsKey($text)) { return $tree.RootOptions[$text] }
            if ($tree.CommonOptions.ContainsKey($text)) { return $tree.CommonOptions[$text] }
            return $null
        }
        function classify_text {
            param($ctx, $tree, $text)
            if (find_option_node $ctx $tree $text) { return 'option' }
            if ($ctx.Next.ContainsKey($text)) { return 'command' }
            return 'unknown'
        }

        $context = $tree.Root
        $used = [System.Collections.Generic.Dictionary[object, int]]::new()
        $tokens = [System.Collections.Generic.List[hashtable]]::new()

        $count = $argTokens.Count
        $lastIndex = $count - 1
        $pending = $null
        $hasPending = $false

        for ($i = 0; $i -lt $count; $i++) {
            $text = $argTokens[$i]
            $isLastUnfinished = ($i -eq $lastIndex) -and -not $treatLastAsComplete
            if ($isLastUnfinished) {
                $pending = @{ text = $text; type = classify_text $context $tree $text }
                $hasPending = $true
                break
            }
            $token = @{ text = $text; type = 'unknown' }
            [void]$tokens.Add($token)

            $optNode = find_option_node $context $tree $text

            if ($optNode) {
                $used[$optNode] = [int]$used[$optNode] + 1
                $token.type = 'option'
                if (node_takes_free_input $optNode) {
                    $i++
                    if ($i -lt $count) {
                        $isValueUnfinished = ($i -eq $lastIndex) -and -not $treatLastAsComplete
                        if ($isValueUnfinished) {
                            $pending = @{ text = $argTokens[$i]; type = 'value' }
                            $hasPending = $true
                            break
                        }
                        $tokens.Add(@{ text = $argTokens[$i]; type = 'value' })
                        $vt = $argTokens[$i]
                        $vo = find_option_node $context $tree $vt
                        if ($vo) { $used[$vo] = [int]$used[$vo] + 1 }
                    }
                }
                elseif (node_has_candidates_after $optNode) {
                    $context = $optNode
                }
            }
            else {
                $childNode = $null
                if ($context.Next.ContainsKey($text)) { $childNode = $context.Next[$text] }
                if ($childNode) {
                    $used[$childNode] = [int]$used[$childNode] + 1
                    $token.type = 'command'
                    $context = $childNode
                }
            }
        }
        $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $tokens) { [void]$seenNames.Add($t.text) }
        if ($hasPending -and -not [string]::IsNullOrEmpty($pending.text)) {
            [void]$seenNames.Add($pending.text)
        }

        $candidateNodes = [System.Collections.Generic.List[object]]::new()
        function add_next_if_not_seen {
            param($items, $namesSet)
            foreach ($n in $items) {
                if ($namesSet.Contains($n.Name)) { continue }
                $skip = $false
                foreach ($a in $n.Alias) { if ($namesSet.Contains($a)) { $skip = $true; break } }
                if ($skip) { continue }
                $candidateNodes.Add($n)
            }
        }
        if ($context -eq $tree.Root) {
            add_next_if_not_seen $tree.Root.NextItems $seenNames
            foreach ($n in $tree.RootOptionItems) { $candidateNodes.Add($n) }
        }
        else {
            add_next_if_not_seen $context.NextItems $seenNames
            $optSource = $context
            if (-not $context.IsOption) {
                while ($optSource.OptionItems.Count -eq 0 -and $null -ne $optSource.Parent) {
                    $optSource = $optSource.Parent
                }
            }
            if ($optSource -eq $tree.Root) {
                foreach ($n in $tree.RootOptionItems) { $candidateNodes.Add($n) }
            }
            else {
                foreach ($n in $optSource.OptionItems) { $candidateNodes.Add($n) }
            }
        }
        foreach ($n in $tree.CommonOptionItems) { $candidateNodes.Add($n) }

        if ($hasPending -and $context.Next.ContainsKey($pending.text)) {
            $matchedNode = $context.Next[$pending.text]
            if (-not $used.ContainsKey($matchedNode) -or $used[$matchedNode] -eq 0) {
                $candidateNodes.Add($matchedNode)
            }
        }

        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($n in $candidateNodes) {
            $usedCount = if ($used.ContainsKey($n)) { $used[$n] } else { 0 }
            if ($n.Repeat -eq 0 -and $usedCount -gt 0) { continue }
            if ($n.Repeat -gt 0 -and $usedCount -ge $n.Repeat) { continue }
            foreach ($it in (expand_node_to_items $n)) { $items.Add($it) }
        }

        if (-not $hasPending -or [string]::IsNullOrEmpty($pending.text)) {
            return @{
                Items   = $items.ToArray()
                Tokens  = $tokens.ToArray()
                Pending = $pending
            }
        }

        $pattern = [System.Management.Automation.WildcardPattern]::Escape($pending.text) + '*'
        return @{
            Items   = $items.Where({ $_.CompletionText -like $pattern })
            Tokens  = $tokens.ToArray()
            Pending = $pending
        }
    }

    if (!$PSCompletions.config.enable_cache) {
        $PSCompletions.completions[$cmd] = $null
        $PSCompletions.completions_data[$cmd] = $null
    }

    if (!$PSCompletions.completions[$cmd]) {
        $language = $PSCompletions.get_language($cmd)
        $PSCompletions.completions[$cmd] = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$cmd/language/$language.json"))
    }

    $PSCompletions.inputs = $inputs

    function handleCompletions { param($completions) return $completions }

    if (!$PSCompletions.completions_data[$cmd]) {
        $PSCompletions.completions_data[$cmd] = build_tree $PSCompletions.completions[$cmd]
    }
    $argTokens = if ($inputs.Count -le 1) { , @() } else { $inputs[1..($inputs.Count - 1)] }
    $matchResult = match_tree $PSCompletions.completions_data[$cmd] $argTokens ($PSCompletions.buffer_before_cursor[-1] -eq ' ')
    $_filter_list = $matchResult.Items
    $PSCompletions.tokens = $matchResult.Tokens
    $PSCompletions.pending = $matchResult.Pending

    if ($cmd -eq 'PSCompletions') {
        $cmds = Get-Command
        $has_command = foreach ($c in $cmds) { if ($c.Name -eq $cmd) { $c; break } }
    }
    else {
        foreach ($c in $PSCompletions.data.alias.$cmd) {
            $has_command = Get-Command $c -ErrorAction Ignore
            if ($has_command) {
                break
            }
        }
    }
    if ($has_command -and $PSCompletions.config.comp_config[$cmd].enable_hooks) { . "$($PSCompletions.path.completions)/$cmd/hooks.ps1" }

    $_filter_list = handleCompletions ([array]$_filter_list)

    $filter_list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $_filter_list) {
        $padSymbols = foreach ($c in $item.symbols) { $PSCompletions.config.$c }
        $padSymbols = if ($padSymbols) { "$($PSCompletions.config.between_item_and_symbol)$($padSymbols -join '')" } else { '' }
        $filter_list.Add(@{
                ListItemText   = $item.ListItemText
                padSymbols     = $padSymbols
                CompletionText = $item.CompletionText
                ToolTip        = $item.ToolTip
            })
    }

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($cmd)) {
        return $filter_list
    }
    if ($PSCompletions.config.enable_completions_sort -and $has_command) {
        $path_order = "$($PSCompletions.path.order)/$cmd.json"
        if ($PSCompletions.order."$($cmd)_job") {
            if ($PSCompletions.order."$($cmd)_job".State -eq 'Completed') {
                $PSCompletions.order[$cmd] = Receive-Job $PSCompletions.order."$($cmd)_job"
                Remove-Job $PSCompletions.order."$($cmd)_job"
                $PSCompletions.order.Remove("$($cmd)_job")
            }
        }
        else {
            if (Test-Path $path_order) {
                try {
                    $PSCompletions.order[$cmd] = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($path_order))
                }
                catch {
                    $PSCompletions.order[$cmd] = $null
                }
            }
            else {
                $PSCompletions.order[$cmd] = $null
            }
        }
        $order = $PSCompletions.order[$cmd]
        if ($order) {
            $PSCompletions.sort_counter = 0
            $filter_list = $filter_list | Sort-Object {
                $PSCompletions.sort_counter--
                $o = $order[$_.CompletionText]
                if ($o) { $o } else { $PSCompletions.sort_counter }
            } -Descending -CaseSensitive
        }
        $PSCompletions.order_job((Get-PSReadLineOption).HistorySavePath, $cmd, $path_order)
    }
    return $filter_list
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_data_by_runspace {
    param([array]$list, [scriptblock]$handler, [scriptblock]$handleResult)
    Add-Member -InputObject $PSCompletions -Force -MemberType ScriptMethod split_array {
        param([array]$array, [int]$count, [bool]$by_count)

        $ChunkSize = if ($by_count) { [math]::Ceiling($array.Length / $count) }else { $count }
        $chunks = for ($i = 0; $i -lt $array.Length; $i += $ChunkSize) {
            , ($array[$i..([math]::Min($i + $ChunkSize - 1, $array.Length - 1))])
        }
        $chunks
    }
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
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_dir {
    param([string]$path)

    if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_language {
    param ([string]$completion)

    if ($PSCompletions.lang_cache.ContainsKey($completion)) {
        return $PSCompletions.lang_cache[$completion]
    }

    $path_config = "$($PSCompletions.path.completions)/$completion/config.json"

    $content_config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
    if (!$content_config.language) {
        $PSCompletions.download_file("completions/$completion/config.json", $path_config, $PSCompletions.urls)
        $content_config = $PSCompletions.get_raw_content($path_config) | ConvertFrom-Json
        $content_config | ConvertTo-Json -Compress | Out-File $path_config -Encoding utf8 -Force
    }
    $config_language = $PSCompletions.config.comp_config[$completion].language
    if ($config_language) {
        $language = if ($config_language -in $content_config.language) { $config_language }else { $content_config.language[0] }
    }
    else {
        $language = if ($PSCompletions.language -in $content_config.language) { $PSCompletions.language }else { $content_config.language[0] }
    }
    $PSCompletions.lang_cache[$completion] = $language
    $language
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_content {
    param ([string]$path)

    $res = (Get-Content $path -Encoding utf8 -ErrorAction Ignore).Where({ $_ -ne '' })
    if ($res) { return $res }
    , @()
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_raw_content {
    param ([string]$path, [bool]$trim = $true)

    $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction Ignore
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
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

    $color_list = @()
    $str = $str -replace "`n", $PSCompletions.guid
    $str_list = foreach ($_ in ($str -split '(<\@[^>]+>.*?(?=<\@|$))').Where({ $_ -ne '' })) {
        if ($_ -match '<\@([\s\w]+)>(.*)') {
            ($matches[2] -replace $PSCompletions.guid, "`n") -replace '^<\@>', ''
            $color = $matches[1] -split ' '
            $color_list += @{color = $color[0]; bgColor = $color[1] }
        }
        else {
            ($_ -replace $PSCompletions.guid, "`n") -replace '^<\@>', ''
            $color_list += @{color = $null; bgColor = $null }
        }
    }
    $str_list = @($str_list)
    for ($i = 0; $i -lt $str_list.Count; $i++) {
        $param = @{
            Object    = $str_list[$i]
            NoNewline = $true
        }
        if ($color_list[$i]['color']) { $param['ForegroundColor'] = $color_list[$i]['color'] }
        if ($color_list[$i]['bgColor']) { $param['BackgroundColor'] = $color_list[$i]['bgColor'] }
        Microsoft.PowerShell.Utility\Write-Host @param
    }
    Microsoft.PowerShell.Utility\Write-Host ''
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_file {
    param([string]$path, [string]$file, [array]$baseUrl)
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

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
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

    $PSCompletions.has_add_completion = $log -and $true

    $PSCompletions.completions_data[$completion] = $null
    $PSCompletions.completions[$completion] = $null
    $PSCompletions.lang_cache.Remove($completion)

    $url = "completions/$completion"

    $completion_dir = Join-Path $PSCompletions.path.completions $completion

    $is_exist = Test-Path $completion_dir
    if ($is_exist -and (Get-Item $completion_dir).LinkType) {
        return
    }

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

    $files = @()
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
                $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($download_info.file)) | ConvertTo-Json -Compress -Depth 100 | Out-File $download_info.file -Encoding utf8 -Force
            }
        }
        catch {
            Remove-Item $completion_dir -Force -Recurse -ErrorAction Ignore
            throw $_
        }
    }

    (Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 | ConvertFrom-Json).update.$completion | Out-File "$completion_dir/.update" -Encoding utf8 -Force

    $done = if ($is_exist) { $PSCompletions.info.update.done }else { $PSCompletions.info.add.done }

    if ($completion -notin $PSCompletions.data.list) {
        $PSCompletions.data.list += $completion
        $PSCompletions.need_update_data = $true
    }
    if (!$PSCompletions.data.alias[$completion]) {
        $PSCompletions.data.alias[$completion] = @()
    }

    $conflict_alias = @()
    if ($config.alias) {
        foreach ($a in $config.alias) {
            if ($a -notin $PSCompletions.data.alias[$completion]) {
                $PSCompletions.data.alias[$completion] += $a
                if ($PSCompletions.data.aliasMap[$a]) {
                    $conflict_alias += $a
                }
                else {
                    $PSCompletions.data.aliasMap.$a = $completion
                }
                $PSCompletions.need_update_data = $true
            }
        }
    }
    else {
        if ($completion -notin $PSCompletions.data.alias[$completion]) {
            $PSCompletions.data.alias[$completion] += $completion
            if ($PSCompletions.data.aliasMap[$completion]) {
                $conflict_alias += $completion
            }
            else {
                $PSCompletions.data.aliasMap[$completion] = $completion
            }
            $PSCompletions.need_update_data = $true
        }
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
            $PSCompletions.config.comp_config[$completion] = [ordered]@{}
        }
        foreach ($_ in $json.config) {
            if (!$PSCompletions.config.comp_config[$completion].$($_.name)) {
                $PSCompletions.config.comp_config[$completion].$($_.name) = $_.value
                $PSCompletions.need_update_data = $true
            }
        }
    }
    if ($null -ne $config.hooks) {
        if (!$PSCompletions.config.comp_config[$completion]) {
            $PSCompletions.config.comp_config[$completion] = [ordered]@{}
        }
        if ($null -eq $PSCompletions.config.comp_config[$completion].enable_hooks) {
            $PSCompletions.config.comp_config[$completion].enable_hooks = [int]$config.hooks
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod init_data {
    $PSCompletions.completions = @{}
    $PSCompletions.lang_cache = @{}
    $PSCompletions.data = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($PSCompletions.path.data))
    if ($null -eq $PSCompletions.data.config) {
        function new_data {
            $data = [ordered]@{
                list     = @()
                alias    = [ordered]@{}
                aliasMap = [ordered]@{}
                config   = $PSCompletions.default_config
            }
            $data.config.comp_config = [ordered]@{}
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
                $data.config.comp_config.$name = [ordered]@{}
                foreach ($_ in $json.config) {
                    $data.config.comp_config.$name.$($_.name) = $_.value
                }
                if ($null -ne $config.hooks) {
                    $data.config.comp_config.$name.enable_hooks = [int]$config.hooks
                }
            }
            $data | ConvertTo-Json -Depth 10 | Out-File $PSCompletions.path.data -Force -Encoding utf8
            $PSCompletions.data = $data

            function download_list {
                $PSCompletions.ensure_dir($PSCompletions.path.temp)
                if (!(Test-Path $PSCompletions.path.completions_json)) {
                    @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
                }
                $current_list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list
                if ($null -eq $current_list) { $current_list = @() }

                $params = @{ ErrorAction = 'Stop' }
                if ($PSEdition -eq 'Core') { $params['OperationTimeoutSeconds'] = 30 }else { $params['TimeoutSec'] = 30 }

                $isErr = $true
                $errMsg = @()
                foreach ($url in $PSCompletions.urls) {
                    $params['Uri'] = "$url/completions.json"
                    try {
                        $response = Invoke-RestMethod @params
                    }
                    catch {
                        $errMsg += $_.Exception.Message
                        continue
                    }
                    $remote_list = $response.list
                    try {
                        $diff = Compare-Object $remote_list $current_list -PassThru
                        if ($diff) {
                            $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8 -ErrorAction Stop
                        }
                        else {
                            Clear-Content $PSCompletions.path.change -Force -ErrorAction Ignore
                        }
                        $PSCompletions.list = $remote_list
                        $new = $response | ConvertTo-Json -Compress -Depth 10
                        $old = Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10
                        if ($new -ne $old) {
                            $new | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force -ErrorAction Stop
                        }
                        $isErr = $false
                        return $remote_list
                    }
                    catch {
                        Write-Host $_.Exception.Message -ForegroundColor Red
                        return $false
                    }
                }
                if ($isErr) {
                    $errMsg | ForEach-Object { Write-Host $_ -ForegroundColor Red }
                    return $false
                }
            }

            $null = download_list
        }
        new_data
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

    $PSCompletions.list = (ConvertFrom-Json $PSCompletions.get_raw_content($PSCompletions.path.completions_json)).list
    $PSCompletions.update = $PSCompletions.get_content($PSCompletions.path.update)
    $PSCompletions.change = $PSCompletions.get_content($PSCompletions.path.change)

    if ('psc' -notin $PSCompletions.data.list) {
        $PSCompletions.add_completion('psc', $false)
        $PSCompletions.data | ConvertTo-Json -Depth 10 | Out-File $PSCompletions.path.data -Force -Encoding utf8
        $PSCompletions.info = $PSCompletions.completions.psc.info
    }
    else {
        $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }
        $PSCompletions.info = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/psc/language/$language.json")).info
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod resolve_tip_enabled {
    if ($this.by_TabExpansion2) {
        return $PSCompletions.config.enable_tip_when_enhance
    }
    if ($PSCompletions.config.comp_config) {
        $enable_tip = $PSCompletions.config.comp_config[$PSCompletions.cmd].enable_tip
        if ($null -ne $enable_tip) { return $enable_tip }
    }
    $PSCompletions.config.enable_tip
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_powershell_menu {
    param([array]$filter_list)
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

    if ($Host.UI.RawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        return ''
    }

    $json = $PSCompletions.completions.$($PSCompletions.cmd)
    $info = $json.info

    $PSCompletions.menu.is_show_tip = $PSCompletions.menu.resolve_tip_enabled()

    $suffix = $PSCompletions.config.completion_suffix
    if ($PSCompletions.menu.is_show_tip) {
        foreach ($_ in $filter_list) {
            $tip = if ($null -eq $_.ToolTip) { ' ' } else {
                $result = $PSCompletions.replace_content($_.ToolTip -join "`n")
                if ($result) { $result } else { ' ' }
            }
            [System.Management.Automation.CompletionResult]::new("$($_.CompletionText)$suffix", ($_.ListItemText + $_.padSymbols), [System.Management.Automation.CompletionResultType]::ParameterValue, $tip)
        }
    }
    else {
        foreach ($_ in $filter_list) {
            [System.Management.Automation.CompletionResult]::new("$($_.CompletionText)$suffix", ($_.ListItemText + $_.padSymbols), [System.Management.Automation.CompletionResultType]::ParameterValue, ' ')
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod argc_completions {
    param([array]$completions)
    foreach ($c in $completions) {
        $aliasList = @($c)
        $alias = Get-Alias -Definition $c -ErrorAction Ignore
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

                $alias = Get-Alias -Name $words[0] -ErrorAction Ignore
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

                $suffix = $PSCompletions.config.completion_suffix

                foreach ($_ in @((argc --argc-compgen powershell $emptyS $words) -split "`n")) {
                    $parts = $_ -split "`t"
                    if ($PSCompletions.config.enable_tip_when_enhance) {
                        $tip = if ('' -eq $parts[3]) { ' ' }else { $parts[3] }
                        [System.Management.Automation.CompletionResult]::new("$($parts[0])$suffix", $parts[0], [System.Management.Automation.CompletionResultType]::ParameterValue, $tip)
                    }
                    else {
                        [System.Management.Automation.CompletionResult]::new("$($parts[0])$suffix", $parts[0], [System.Management.Automation.CompletionResultType]::ParameterValue, ' ')
                    }
                }
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod wrap_whitespace {
    param([string]$String)
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
    if ($PSCompletions.path.root -like "$env:ProgramFiles*" -or $PSCompletions.path.root -like "$env:SystemRoot*") {
        if (-not [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Microsoft.PowerShell.Utility\Write-Host -ForegroundColor Red @"

[PSCompletions] Administrator Rights Required
-------------------------------------------------
PSCompletions is installed in a system-level directory.
Location: $($PSCompletions.path.root)

To use PSCompletions normally, please:
1. Run PowerShell as Administrator.
2. Or reinstall the module to a user-writable location via '-Scope CurrentUser'.

Refer to: https://pscompletions.abgox.com/docs/require-admin

"@
            return
        }
    }

    # Windows...
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

        $PSCompletions.use_module_completion_menu = $PSCompletions.config.enable_menu
        if ($PSCompletions.config.enable_menu -and $PSCompletions.config.enable_menu_enhance) {
            Set-PSReadLineKeyHandler -Key $PSCompletions.config.trigger_key -ScriptBlock $PSCompletions.menu.module_completion_menu_script
        }
        else {
            Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete
            $keys = $PSCompletions.data.aliasMap.keys
            foreach ($k in $keys) {
                Register-ArgumentCompleter -Native -CommandName $k -ScriptBlock {
                    # param($wordToComplete, $commandAst, $cursorPosition)
                    $buffer = ''
                    $cursor = 0
                    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)
                    if (-not $buffer) { return }

                    $PSCompletions.buffer = $buffer
                    $PSCompletions.buffer_after_cursor = $buffer.Substring($cursor)
                    $buffer = $PSCompletions.buffer_before_cursor = $buffer.Substring(0, $cursor)
                    $inputs = @()
                    $matches = [regex]::Matches($buffer, $PSCompletions.input_pattern)
                    foreach ($match in $matches) { $inputs += $match.Value }

                    if (!$inputs) { return }

                    $PSCompletions.alias = $inputs[0]
                    $PSCompletions.cmd = $cmd = $PSCompletions.data.aliasMap[$inputs[0]]

                    $filter_list = $PSCompletions.get_completion($cmd, $inputs)

                    $PSCompletions.menu.by_TabExpansion2 = $false

                    if ($PSCompletions.config.enable_menu) {
                        if ($PSCompletions.config.completions_confirm_limit -gt 0 -and $filter_list.Count -gt $PSCompletions.config.completions_confirm_limit) {
                            $count = $filter_list.Count
                            $tip = $PSCompletions.replace_content($PSCompletions.info.module.too_many_completions.tip)
                            $_filter_list = foreach ($t in $PSCompletions.info.module.too_many_completions.text) {
                                $text = $PSCompletions.replace_content($t)
                                @{
                                    CompletionText = $text
                                    ListItemText   = $text
                                    ToolTip        = $tip
                                }
                            }
                            $result = $PSCompletions.menu.show_module_menu($_filter_list)
                            if (!$result) {
                                return ''
                            }
                        }
                        $PSCompletions.menu.show_module_menu($filter_list)
                    }
                    else {
                        $PSCompletions.menu.show_powershell_menu($filter_list)
                    }
                }
            }
        }
    }

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
            if ($menu.is_show_tip -and $menu.cursor_to_top -lt $menu.ui_height + 6 -and $menu.ui_height -gt 9) {
                $menu.ui_height -= 5
            }
            $menu.pos.Y = [Math]::Max(0, $rawUI.CursorPosition.Y - $menu.ui_height - $config.height_from_menu_bottom_to_cursor_when_above)
        }
        else {
            if ($menu.cursor_to_bottom -lt $menu.ui_height) {
                $menu.ui_height = $menu.cursor_to_bottom
            }
            $list_limit = if ($config.list_max_count_when_below -gt 0) { $config.list_max_count_when_below + 2 }else { 12 }
            if ($list_limit -lt $menu.ui_height) {
                $menu.ui_height = $list_limit
            }
            if ($menu.is_show_tip -and $menu.cursor_to_bottom -lt $menu.ui_height + 6 -and $menu.ui_height -gt 9) {
                $menu.ui_height -= 5
            }
            $menu.pos.Y = $rawUI.CursorPosition.Y + 1 + $config.height_from_menu_top_to_cursor_when_below
        }
        $menu.page_max_index = $menu.ui_height - 3
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_menu_buffer {
        param($startPos, $endPos)
        $top = [System.Management.Automation.Host.Coordinates]::new($startPos.X, $startPos.Y)
        $bottom = [System.Management.Automation.Host.Coordinates]::new($endPos.X , $endPos.Y)
        $buffer = $rawUI.GetBufferContents([System.Management.Automation.Host.Rectangle]::new($top, $bottom))
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
            $text = $item.ListItemText -replace '\x1B\[[\d;]*m', ''
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

        $content = @($start, $filter, $end) -join ''
        $width = $rawUI.LengthInBufferCells($content)

        $prevWidth = if ($menu.filter_buffer_width) { $menu.filter_buffer_width } else { 0 }
        if ($prevWidth -gt $width) {
            $clearContent = '─' * $prevWidth
            $rawUI.SetBufferContents(
                @{ X = $menu.pos.X + 2; Y = $menu.pos.Y },
                $rawUI.NewBufferCellArray(@($clearContent), $config.border_color, $bgColor)
            )
        }
        $menu.filter_buffer_width = [Math]::Max($width, $prevWidth)
        $rawUI.SetBufferContents(
            @{ X = $menu.pos.X + 2; Y = $menu.pos.Y },
            $rawUI.NewBufferCellArray(@($content), $config.filter_color, $bgColor)
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
            if ($rest_line -le 0) { return }

            $tip = $menu.filter_list[$index].ToolTip

            if ($null -eq $tip) { return }

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

            $json = $PSCompletions.completions[$PSCompletions.cmd]
            $info = $json.info

            $tip_arr = @()
            $tip = ($tip -join "`n").Trim().Replace("`r`n", "`n") -replace '\x1B\[[\d;]*m', ''
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

                $tip_arr += $outputString.Split("`n")
            }

            if (-not ($tip_arr -join '')) { return }

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
                if ($pos.Y -ge $rawUI.BufferSize.Height - 1) { return }
            }
            $rawUI.SetBufferContents($pos, $rawUI.NewBufferCellArray($tip_arr, $config.tip_color, $bgColor))
        }
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_menu_selection {

        if ($menu.old_selection) {
            $rawUI.SetBufferContents($menu.old_selection.pos, $menu.old_selection.buffer)
        }

        $X = $menu.pos.X + 1
        $to_X = $X + $menu.list_max_width - 1
        $Y = $menu.pos.Y + 1 + $menu.page_current_index
        $Rectangle = [System.Management.Automation.Host.Rectangle]::new($X, $Y, $to_X, $Y)
        $LineBuffer = $rawUI.GetBufferContents($Rectangle)
        $menu.old_selection = @{
            pos    = @{X = $X; Y = $Y }
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
            if ($menu.filter_list.Count - $menu.page_max_index -le 0) { return }
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

                    ui_height          = $menu.ui_height
                    pos_y              = $menu.pos.Y
                }
            }
        }
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_menu_output {
        param($item)
        $out = $item.CompletionText.Trim()
        # psc add
        if ($null -eq $item.ResultType) {
            if ($PSCompletions.buffer_after_cursor -match '^\s+[^\s]') {
                return $out
            }
            return "$out$suffix"
        }

        if ($item.ResultType -in
            [System.Management.Automation.CompletionResultType]::Method,
            [System.Management.Automation.CompletionResultType]::Property,
            [System.Management.Automation.CompletionResultType]::Variable,
            [System.Management.Automation.CompletionResultType]::Type,
            [System.Management.Automation.CompletionResultType]::Namespace
        ) {
            return $out
        }

        # Directory, registry key, or other container types
        $_out = $null
        if ($item.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            if ($config.enable_path_with_trailing_separator) {
                if ($out.Length -ge 1 -and $out[-1] -match "^['`"]$") {
                    if ($out.Length -ge 2 -and $out[-2] -match '^[/\\]$') {
                        $_out = $out
                    }
                    else {
                        $_out = $out.Insert($out.Length - 1, $PSCompletions.separator)
                    }
                }
                else {
                    $_out = $out + $PSCompletions.separator
                }
            }
            else {
                $_out = $out
            }
        }
        if ($_out) {
            $lastChar = $_out[-1]
            if ($lastChar -in '"', "'" -and $lastChar -eq [regex]::Matches($PSCompletions.buffer_after_cursor, $PSCompletions.input_pattern)[0].Value) {
                return $_out -replace "$lastChar`$", ''
            }
            return $_out
        }

        # File or other leaf items (e.g., registry values)
        # [System.Management.Automation.CompletionResultType]::ProviderItem

        # [System.Management.Automation.CompletionResultType]::Command

        # [System.Management.Automation.CompletionResultType]::ParameterName

        # [System.Management.Automation.CompletionResultType]::ParameterValue

        # if foreach switch ...
        # [System.Management.Automation.CompletionResultType]::Keyword

        # [System.Management.Automation.CompletionResultType]::Text

        if ($PSCompletions.buffer_after_cursor -match '^\s+[^\s]') {
            return $out
        }
        else {
            $lastChar = $out[-1]
            if ($lastChar -in '"', "'" -and $lastChar -eq [regex]::Matches($PSCompletions.buffer_after_cursor, $PSCompletions.input_pattern)[0].Value) {
                return $out -replace "$lastChar`$", ''
            }
        }

        return "$out$suffix"
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
        param($filter_list)
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

        if (!$filter_list) { return '' }

        $menu = $PSCompletions.menu
        $config = $PSCompletions.config
        $rawUI = $Host.UI.RawUI
        $bgColor = $rawUI.BackgroundColor

        $suffix = $config.completion_suffix

        $menu.pos = @{ X = 0; Y = 0 }

        $menu.ui_height = 0

        $menu.filter = ''
        $menu.filter_buffer_width = 0
        $menu.page_current_index = 0
        $menu.selected_index = 0
        $menu.offset = 0

        # 记录每一次过滤的数据
        $menu.data = [System.Collections.Generic.List[System.Object]]::new()
        $menu.no_match_count = 0

        $menu.is_show_tip = $PSCompletions.menu.resolve_tip_enabled()

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
                if ($len -gt $maxWidth) { $maxWidth = $len }
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
        $menu.cursor_to_bottom = $rawUI.BufferSize.Height - $rawUI.CursorPosition.Y - 1 - $config.height_from_menu_top_to_cursor_when_below
        $menu.cursor_to_top = $rawUI.CursorPosition.Y - $config.height_from_menu_bottom_to_cursor_when_above - 1

        $menu.is_show_above = $menu.cursor_to_top -gt $menu.cursor_to_bottom
        if ($menu.is_show_above -and $config.enable_menu_show_below) {
            [Microsoft.PowerShell.PSConsoleReadLine]::ClearScreen()
            $menu.cursor_to_bottom = $rawUI.BufferSize.Height - $rawUI.CursorPosition.Y - 1 - $config.height_from_menu_top_to_cursor_when_below
            $menu.cursor_to_top = $rawUI.CursorPosition.Y - $config.height_from_menu_bottom_to_cursor_when_above - 1

            $menu.is_show_above = $menu.cursor_to_top -gt $menu.cursor_to_bottom
        }
        if ($menu.is_show_above) {
            $startY = 0
            $endY = $menu.cursor_to_top
        }
        else {
            $startY = $rawUI.CursorPosition.Y + 1
            $endY = $rawUI.BufferSize.Height - 1
        }
        $menu.buffer_start = [System.Management.Automation.Host.Coordinates]::new(0, $startY)
        $menu.buffer_end = [System.Management.Automation.Host.Coordinates]::new($rawUI.BufferSize.Width - 1, $endY)

        $menu.parse_menu_list()

        # 菜单高度小于 3 (上下边框 + 1个补全项)
        if ($menu.ui_height -lt 3) {
            [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
            return ''
        }
        $current_encoding = [console]::OutputEncoding
        [console]::OutputEncoding = $PSCompletions.menu.encoding

        # 记录 buffer
        $menu.origin_full_buffer = $menu.get_menu_buffer($menu.buffer_start, $menu.buffer_end)

        # 显示菜单
        $menu.new_menu_border_buffer()
        $menu.new_menu_list_buffer($menu.offset)
        $menu.new_menu_tip_buffer($menu.selected_index)
        $menu.new_menu_status_buffer()
        $menu.new_menu_filter_buffer($menu.filter)
        $menu.set_menu_selection()

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
                # 38: Up
                # 85: Ctrl + u
                # 80: Ctrl + p
                # 75: Ctrl + k
                { $_ -eq 38 -or ($pressCtrl -and $_ -in @(85, 80, 75)) } {
                    $menu.move_menu_selection($false)
                    break
                }
                # 向下
                # 40: Down
                # 68: Ctrl + d
                # 78: Ctrl + n
                # 74: Ctrl + j
                { $_ -eq 40 -or ($pressCtrl -and $_ -in @(68, 78, 74)) } {
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
                            if ($menu.no_match_count -gt 0) {
                                $menu.no_match_count--
                                $menu.new_menu_filter_buffer($menu.filter)
                            }
                            else {
                                if ($menu.data.Count -gt 1) {
                                    $old_buffer = $menu.data[-2].old_full_buffer
                                    $rawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                                    $menu.data.RemoveAt($menu.data.Count - 1)
                                    $menu.handle_menu_data('get')
                                }
                                else {
                                    $old_buffer = $menu.data[0].old_full_buffer
                                    $rawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                                    $menu.data.Clear()
                                    $menu.old_selection = $null
                                    $menu.offset = 0
                                    $menu.selected_index = 0
                                    $menu.page_current_index = 0
                                }
                            }
                        }
                        else {
                            $menu.reset_menu()
                            ''
                            break loop
                        }
                    }
                    else {
                        # add
                        if ($config.enable_filter_subsequence_match) {
                            $menu.filter += $PressKey.Character
                            $isPrefix = $menu.filter.Length -ge 1 -and $menu.filter[0] -eq '^'
                            $subSeq = if ($isPrefix) { $menu.filter.Substring(1) } else { $menu.filter }
                            $comparison = {
                                param($text)
                                if ($isPrefix) {
                                    if ($subSeq.Length -eq 0) { return $true }
                                    if ([char]::ToLower($text[0]) -ne [char]::ToLower($subSeq[0])) { return $false }
                                }
                                $ti = if ($isPrefix) { 1 } else { 0 }
                                $fi = if ($isPrefix) { 1 } else { 0 }
                                while ($ti -lt $text.Length -and $fi -lt $subSeq.Length) {
                                    if ([char]::ToLower($text[$ti]) -eq [char]::ToLower($subSeq[$fi])) { $fi++ }
                                    $ti++
                                }
                                $fi -eq $subSeq.Length
                            }
                        }
                        else {
                            if ($menu.filter -match '\*$' -and $PressKey.Character -eq '*') { break }
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
                            $no_match_limit = $config.enter_when_no_match_after
                            if ($no_match_limit -gt 0) {
                                $menu.no_match_count++
                                $menu.new_menu_filter_buffer($menu.filter)
                                if ($menu.no_match_count -ge $no_match_limit) {
                                    $out = $menu.filter
                                    $menu.reset_menu()
                                    $out
                                    break loop
                                }
                                $menu.filter_list = $menu.data[-1].filter_list
                            }
                            else {
                                $menu.filter = $menu.data[-1].filter
                                $menu.filter_list = $menu.data[-1].filter_list
                                $menu.new_menu_filter_buffer($menu.filter)
                            }
                        }
                        else {
                            $menu.no_match_count = 0
                            $menu.reset_menu($false)
                            $menu.parse_menu_list()
                            $menu.new_menu_border_buffer()
                            $menu.new_menu_list_buffer($menu.offset)
                            $menu.new_menu_tip_buffer($menu.selected_index)
                            $menu.new_menu_status_buffer()
                            $menu.new_menu_filter_buffer($menu.filter)
                            $menu.set_menu_selection()

                            $menu.handle_menu_data('add')
                        }
                    }
                    break
                }
            }
        }
        [console]::OutputEncoding = $current_encoding
    }
}
else {
    # WSL/Unix...
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

        $PSCompletions.use_module_completion_menu = 0
        # XXX: 非 Windows 平台，暂时只能使用默认的补全菜单
        Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete

        $keys = $PSCompletions.data.aliasMap.keys
        foreach ($k in $keys) {
            Register-ArgumentCompleter -Native -CommandName $k -ScriptBlock {
                # param($wordToComplete, $commandAst, $cursorPosition)
                $buffer = ''
                $cursor = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)
                if (-not $buffer) { return }

                $PSCompletions.buffer = $buffer
                $PSCompletions.buffer_after_cursor = $buffer.Substring($cursor)
                $buffer = $PSCompletions.buffer_before_cursor = $buffer.Substring(0, $cursor)
                $inputs = @()
                $matches = [regex]::Matches($buffer, $PSCompletions.input_pattern)
                foreach ($match in $matches) { $inputs += $match.Value }

                if (!$inputs) { return }

                $PSCompletions.cmd = $cmd = $PSCompletions.data.aliasMap[$inputs[0]]
                $filter_list = $PSCompletions.get_completion($cmd, $inputs)
                $PSCompletions.menu.by_TabExpansion2 = $false
                $PSCompletions.menu.show_powershell_menu($filter_list)
            }
        }
    }
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

    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ConvertFrom_JsonAsHashtable {
        param([string]$json)
        ConvertFrom-Json $json -AsHashtable
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod start_job {
        $PSCompletions.job = Start-ThreadJob -ScriptBlock {
            param($PSCompletions)

            function download_list {
                if (!(Test-Path $PSCompletions.path.completions_json)) {
                    @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
                }
                $current_list = ($PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json).list
                if ($null -eq $current_list) { $current_list = @() }
                $isErr = $true
                foreach ($url in $PSCompletions.urls) {
                    try {
                        $response = Invoke-RestMethod -Uri "$url/completions.json" -OperationTimeoutSeconds 30 -ErrorAction Stop
                    }
                    catch { continue }
                    $remote_list = $response.list
                    $diff = Compare-Object $remote_list $current_list -PassThru
                    if ($diff) {
                        $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8 -ErrorAction Stop
                    }
                    else {
                        Clear-Content $PSCompletions.path.change -Force -ErrorAction Ignore
                    }
                    $PSCompletions.list = $remote_list
                    $new = $response | ConvertTo-Json -Compress -Depth 10
                    $old = Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10
                    if ($new -ne $old) {
                        $new | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force -ErrorAction Stop
                    }
                }
            }

            $PSCompletions.ensure_dir($PSCompletions.path.temp)
            $PSCompletions.ensure_dir($PSCompletions.path.order)
            $PSCompletions.ensure_dir("$($PSCompletions.path.completions)/psc")

            $PSCompletions.path.change, $PSCompletions.path.update | ForEach-Object {
                if (!(Test-Path $_)) { '' | Out-File $_ -Force -Encoding utf8 }
            }

            download_list

            foreach ($_ in $PSCompletions.data.list) {
                $completion_dir = "$($PSCompletions.path.completions)/$_"
                try {
                    $item = Get-Item $completion_dir -ErrorAction Stop
                }
                catch {
                    continue
                }

                if ($null -ne $item.LinkType -and -not (Test-Path $item.Target)) {
                    Remove-Item $completion_dir -Force -Recurse -ErrorAction Ignore
                    continue
                }

                $path = "$completion_dir/config.json"
                if (!(Test-Path $path)) {
                    try {
                        $PSCompletions.download_file("completions/$_/config.json", $path, $PSCompletions.urls)
                    }
                    catch {
                        continue
                    }
                }
                $PSCompletions.ensure_dir("$completion_dir/language")
                $json_config = $PSCompletions.get_raw_content($path) | ConvertFrom-Json
                foreach ($lang in $json_config.language) {
                    $path_lang = "$completion_dir/language/$lang.json"
                    if (!(Test-Path $path_lang)) {
                        $PSCompletions.download_file("completions/$_/language/$lang.json", $path_lang, $PSCompletions.urls)
                    }
                }
                if ($null -ne $json_config.hooks) {
                    $path_hooks = "$completion_dir/hooks.ps1"
                    if (!(Test-Path $path_hooks)) {
                        $PSCompletions.download_file("completions/$_/hooks.ps1", $path_hooks, $PSCompletions.urls)
                    }
                }
            }

            function check_update {
                $currentTime = Get-Date
                $updateInterval = [TimeSpan]::FromHours(6)

                if (Test-Path $PSCompletions.path.last_update) {
                    $lastUpdate = Get-Content $PSCompletions.path.last_update -Encoding utf8 | Get-Date
                    if ($lastUpdate) {
                        $timeSinceLast = $currentTime - $lastUpdate
                        if ($timeSinceLast -lt $updateInterval) {
                            return
                        }
                    }
                }

                # module
                $urls = $PSCompletions.urls + 'https://pscompletions.abgox.com'
                foreach ($url in $urls) {
                    try {
                        $res = Invoke-RestMethod -Uri "$url/module/version.json" -ErrorAction Stop
                        break
                    }
                    catch {}
                }
                if (-not $res) { return }
                $newVersion = $res.version -replace 'v', ''
                if ($newVersion -match '^[\d\.]+$') {
                    $versions = $PSCompletions.version, $newVersion | Sort-Object { [Version] $_ }
                    if ($versions[-1] -ne $PSCompletions.version) {
                        $versions[-1] | Out-File $PSCompletions.path.module_update -Force -Encoding utf8
                    }
                }

                # completions
                $need_update_list = @()
                $update = (Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json).update
                $completion_dirs = Get-ChildItem $PSCompletions.path.completions -Directory
                foreach ($c in $completion_dirs) {
                    $completion = $c.Name
                    if (-not $update.$completion) {
                        continue
                    }
                    $completion_dir = $PSCompletions.path.completions + "/$completion"
                    if (-not (Test-Path $completion_dir) -or (Get-Item $completion_dir).LinkType) {
                        continue
                    }
                    $p = "$completion_dir/.update"
                    if (-not (Test-Path $p)) {
                        $need_update_list += $completion
                        Remove-Item "$($PSCompletions.path.completions)/$completion/guid.json" -Force -ErrorAction Ignore
                        continue
                    }
                    $content = Get-Content $p -Raw -Encoding utf8 -ErrorAction Ignore
                    if ($content -and $content.Trim() -eq $update.$completion) {
                        continue
                    }
                    $need_update_list += $completion
                }
                if ($need_update_list) { $need_update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8 }
                else { Clear-Content $PSCompletions.path.update -Force -ErrorAction Ignore }

                $currentTime.ToString('o') | Out-File $PSCompletions.path.last_update -Force -Encoding utf8
            }

            check_update
        } -ArgumentList $PSCompletions
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod order_job {
        param([string]$history_path, [string]$cmd, [string]$path_order)
        $PSCompletions.order."$($cmd)_job" = Start-ThreadJob -ScriptBlock {
            param($PScompletions, [string]$path_history, [string]$cmd, [string]$path_order)

            $order_dir = $PSCompletions.path.order
            if (!(Test-Path $order_dir)) {
                New-Item -ItemType Directory -Path $order_dir -Force | Out-Null
            }

            $index = 0
            $order = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
            $contents = Get-Content $path_history -Encoding utf8 -ErrorAction Ignore
            foreach ($_ in $contents) {
                $alias = $PSCompletions.data.alias[$cmd]
                if ($null -eq $alias) {
                    $alias = @($cmd)
                }
                foreach ($a in $alias) {
                    if ($_ -match "^[^\S\n]*$a\s+.+") {
                        $_ = $_ -replace '^\w+\s+', ''
                        $inputs = @()
                        $matches = [regex]::Matches($_, $PSCompletions.input_pattern)
                        foreach ($match in $matches) { $inputs += $match.Value }
                        $index += $inputs.Count
                        $i = 0
                        foreach ($completion in $inputs) {
                            $order[$completion] = $index + $i
                            $i--
                        }
                        break
                    }
                }
            }

            $index = 0
            $result = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
            $sorted = $order.Keys | Sort-Object { $order[$_] } -CaseSensitive
            foreach ($_ in $sorted) {
                $index++
                $result[$_] = $index
            }

            $old = Get-Content -Raw $path_order -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json -AsHashtable | ConvertTo-Json -Compress -Depth 10
            $new = $result | ConvertTo-Json -Compress -Depth 10
            if ($new -ne $old) {
                $new | Out-File $path_order -Force -Encoding utf8
            }

            return $result
        } -ArgumentList $PScompletions, $history_path, $cmd, $path_order
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

    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ConvertFrom_JsonAsHashtable {
        param([string]$json)
        # https://github.com/abgox/ConvertFrom-JsonAsHashtable
        function ConvertFrom-JsonAsHashtable {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline = $true)]$InputObject)
            begin { $buffer = [System.Text.StringBuilder]::new() }
            process {
                if ($InputObject -is [array]) { [void]$buffer.AppendLine(($InputObject -join "`n")) }
                else { [void]$buffer.AppendLine($InputObject) }
            }
            end {
                $jsonString = $buffer.ToString().Trim()
                if (-not $jsonString) { return $null }
                if ($PSVersionTable.PSVersion.Major -ge 7) { return ConvertFrom-Json $jsonString -AsHashtable }
                $jsonString = [regex]::Replace($jsonString, '(?<!\\)""\s*:', { '"emptyKey_' + [Guid]::NewGuid() + '":' })
                $jsonString = [regex]::Replace($jsonString, ',\s*(?=[}\]]\s*$)', '')
                $parsed = ConvertFrom-Json $jsonString
                function ConvertRecursively {
                    param($obj)
                    if ($null -eq $obj) { return $null }
                    if ($obj -is [System.Collections.IDictionary]) {
                        $ht = @{}
                        $keys = $obj.Keys
                        foreach ($k in $keys) { $ht[$k] = ConvertRecursively $obj[$k] }
                        return $ht
                    }
                    if ($obj -is [System.Management.Automation.PSCustomObject]) {
                        $ht = @{}
                        $props = $obj.PSObject.Properties
                        foreach ($p in $props) { $ht[$p.Name] = ConvertRecursively $p.Value }
                        return $ht
                    }
                    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string]) -and -not ($obj -is [byte[]])) {
                        $list = [System.Collections.Generic.List[object]]::new()
                        foreach ($item in $obj) { $list.Add((ConvertRecursively $item)) }
                        return , $list.ToArray()
                    }
                    return $obj
                }
                return ConvertRecursively $parsed
            }
        }
        ConvertFrom-JsonAsHashtable $json
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod start_job {
        $PSCompletions.job = Start-Job -ScriptBlock {
            param($PSCompletions)

            function get_raw_content {
                param ([string]$path, [bool]$trim = $true)
                $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction Ignore
                if ($res) {
                    if ($trim) { return $res.Trim() }
                    return $res
                }
                ''
            }
            function download_file {
                param([string]$path, [string]$file, [array]$baseUrl)
                $isErr = $true
                for ($i = 0; $i -lt $baseUrl.Count; $i++) {
                    $item = $baseUrl[$i]
                    $url = $item + '/' + $path
                    try {
                        Invoke-RestMethod -Uri $url -OutFile $file -TimeoutSec 30 -ErrorAction Stop
                        $isErr = $false
                        break
                    }
                    catch {}
                }
                if ($isErr) { throw }
            }
            function ensure_dir {
                param([string]$path)
                if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
            }
            function download_list {
                if (!(Test-Path $PSCompletions.path.completions_json)) {
                    @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
                }
                $current_list = (get_raw_content $PSCompletions.path.completions_json | ConvertFrom-Json).list
                if ($null -eq $current_list) { $current_list = @() }
                foreach ($url in $PSCompletions.urls) {
                    try {
                        $response = Invoke-RestMethod -Uri "$url/completions.json" -TimeoutSec 30 -ErrorAction Stop
                    }
                    catch { continue }
                    $remote_list = $response.list
                    $diff = Compare-Object $remote_list $current_list -PassThru
                    if ($diff) {
                        $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8 -ErrorAction Stop
                    }
                    else {
                        Clear-Content $PSCompletions.path.change -Force -ErrorAction Ignore
                    }
                    $new = $response | ConvertTo-Json -Compress -Depth 10
                    $old = Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10
                    if ($new -ne $old) {
                        $new | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force -ErrorAction Stop
                    }
                }
            }

            ensure_dir $PSCompletions.path.temp
            ensure_dir $PSCompletions.path.order
            ensure_dir "$($PSCompletions.path.completions)/psc"

            $PSCompletions.path.change, $PSCompletions.path.update | ForEach-Object {
                if (!(Test-Path $_)) { '' | Out-File $_ -Force -Encoding utf8 }
            }

            download_list

            foreach ($_ in $PSCompletions.data.list) {
                $completion_dir = "$($PSCompletions.path.completions)/$_"
                try {
                    $item = Get-Item $completion_dir -ErrorAction Stop
                }
                catch {
                    continue
                }
                if ($null -ne $item.LinkType -and -not (Test-Path $item.Target)) {
                    Remove-Item $completion_dir -Force -Recurse -ErrorAction Ignore
                    continue
                }
                $path = "$completion_dir/config.json"
                if (!(Test-Path $path)) {
                    try {
                        download_file "completions/$_/config.json" $path $PSCompletions.urls
                    }
                    catch {
                        continue
                    }
                }
                ensure_dir "$completion_dir/language"
                $json_config = get_raw_content $path | ConvertFrom-Json
                foreach ($lang in $json_config.language) {
                    $path_lang = "$completion_dir/language/$lang.json"
                    if (!(Test-Path $path_lang)) {
                        download_file "completions/$_/language/$lang.json" $path_lang $PSCompletions.urls
                    }
                }
                if ($null -ne $json_config.hooks) {
                    $path_hooks = "$completion_dir/hooks.ps1"
                    if (!(Test-Path $path_hooks)) {
                        download_file "completions/$_/hooks.ps1" $path_hooks $PSCompletions.urls
                    }
                }
            }

            function check_update {
                $currentTime = Get-Date
                $updateInterval = [TimeSpan]::FromHours(6)

                if (Test-Path $PSCompletions.path.last_update) {
                    $lastUpdate = Get-Content $PSCompletions.path.last_update -Encoding utf8 | Get-Date
                    if ($lastUpdate) {
                        $timeSinceLast = $currentTime - $lastUpdate
                        if ($timeSinceLast -lt $updateInterval) {
                            return
                        }
                    }
                }

                # module
                $urls = $PSCompletions.urls + 'https://pscompletions.abgox.com'
                foreach ($url in $urls) {
                    try {
                        $res = Invoke-RestMethod -Uri "$url/module/version.json" -ErrorAction Stop
                        break
                    }
                    catch {}
                }
                if (-not $res) { return }
                $newVersion = $res.version -replace 'v', ''
                if ($newVersion -match '^[\d\.]+$') {
                    $versions = $PSCompletions.version, $newVersion | Sort-Object { [Version] $_ }
                    if ($versions[-1] -ne $PSCompletions.version) {
                        $versions[-1] | Out-File $PSCompletions.path.module_update -Force -Encoding utf8
                    }
                }

                # completions
                $need_update_list = @()
                $update = (Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json).update
                $completion_dirs = Get-ChildItem $PSCompletions.path.completions -Directory
                foreach ($c in $completion_dirs) {
                    $completion = $c.Name
                    if (-not $update.$completion) {
                        continue
                    }
                    $completion_dir = $PSCompletions.path.completions + "/$completion"
                    if (-not (Test-Path $completion_dir) -or (Get-Item $completion_dir).LinkType) {
                        continue
                    }
                    $p = "$completion_dir/.update"
                    if (-not (Test-Path $p)) {
                        $need_update_list += $completion
                        Remove-Item "$($PSCompletions.path.completions)/$completion/guid.json" -Force -ErrorAction Ignore
                        continue
                    }
                    $content = Get-Content $p -Raw -Encoding utf8 -ErrorAction Ignore
                    if ($content -and $content.Trim() -eq $update.$completion) {
                        continue
                    }
                    $need_update_list += $completion
                }
                if ($need_update_list) { $need_update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8 }
                else { Clear-Content $PSCompletions.path.update -Force -ErrorAction Ignore }

                $currentTime.ToString('o') | Out-File $PSCompletions.path.last_update -Force -Encoding utf8
            }
            check_update
        } -ArgumentList $PSCompletions
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod order_job {
        param([string]$history_path, [string]$cmd, [string]$path_order)
        $PSCompletions.order."$($cmd)_job" = Start-Job -ScriptBlock {
            param($PScompletions, [string]$path_history, [string]$cmd, [string]$path_order)

            $order_dir = $PSCompletions.path.order
            if (!(Test-Path $order_dir)) {
                New-Item -ItemType Directory -Path $order_dir -Force | Out-Null
            }

            # XXX 这里不能直接使用 $PSCompletions.input_pattern，实测会导致排序失效
            $input_pattern = [regex]::new("(?:`"[^`"]*`"|'[^']*'|\S)+", [System.Text.RegularExpressions.RegexOptions]::Compiled)

            $index = 0
            $order = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
            $contents = Get-Content $path_history -Encoding utf8 -ErrorAction Ignore
            foreach ($_ in $contents) {
                $alias = $PSCompletions.data.alias[$cmd]
                if ($null -eq $alias) {
                    $alias = @($cmd)
                }
                foreach ($a in $alias) {
                    if ($_ -match "^[^\S\n]*$a\s+.+") {
                        $_ = $_ -replace '^\w+\s+', ''
                        $inputs = @()
                        $matches = [regex]::Matches($_, $input_pattern)
                        foreach ($match in $matches) { $inputs += $match.Value }
                        $index += $inputs.Count
                        $i = 0
                        foreach ($completion in $inputs) {
                            $order[$completion] = $index + $i
                            $i--
                        }
                        break
                    }
                }
            }

            $index = 0
            $result = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
            $sorted = $order.Keys | Sort-Object { $order[$_] } -CaseSensitive
            foreach ($_ in $sorted) {
                $index++
                $result[$_] = $index
            }

            $old = Get-Content -Raw $path_order -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10
            $new = $result | ConvertTo-Json -Compress -Depth 10
            if ($new -ne $old) {
                $new | Out-File $path_order -Force -Encoding utf8
            }

            return $result
        } -ArgumentList $PScompletions, $history_path, $cmd, $path_order
    }
}

if (!(Test-Path $PSCompletions.path.order)) {
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod move_old_version {
        $version = (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent) -ErrorAction Ignore).Name | Sort-Object { [Version]$_ } -ErrorAction Ignore | Where-Object { $_ -match '^\d+\.\d.*' }
        if ($version -is [array]) {
            $old_version = $version[-2]
            if ($old_version -match '^\d+\.\d.*' -and $old_version -ge '4') {
                $old_version_dir = Join-Path (Split-Path $PSCompletions.path.root -Parent) $old_version

                if (Test-Path "$old_version_dir/data.json") {
                    Move-Item "$old_version_dir/data.json" $PSCompletions.path.data -Force -ErrorAction Ignore
                }
                else {
                    $data = [ordered]@{
                        list     = @()
                        alias    = [ordered]@{}
                        aliasMap = [ordered]@{}
                        config   = $PSCompletions.default_config
                    }
                    $data.config.comp_config = [ordered]@{}
                    $items = Get-ChildItem -Path "$old_version_dir/completions" -ErrorAction Ignore
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
                    $data | ConvertTo-Json -Depth 10 | Out-File $PSCompletions.path.data -Force -Encoding utf8
                }
                Get-ChildItem "$old_version_dir/completions" -Directory | ForEach-Object {
                    if ($_.Name -ne 'psc') {
                        Move-Item $_.FullName $PSCompletions.path.completions -Force -ErrorAction Ignore
                    }
                }
                Get-ChildItem "$old_version_dir/temp" | ForEach-Object {
                    if ($_.Name -ne 'completions.json') {
                        Move-Item $_.FullName $PSCompletions.path.temp -Force -ErrorAction Ignore
                    }
                }
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
    $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.description))
}
$PSCompletions.handle_completion()
if ($PSCompletions.config.enable_auto_alias_setup) {
    $Matches = $PSCompletions.data.aliasMap.Keys
    foreach ($_ in $Matches) {
        $args = $PSCompletions.data.aliasMap[$_]
        if ($args -eq 'psc') {
            Microsoft.PowerShell.Utility\Set-Alias $_ PSCompletions -Force -ErrorAction Ignore
        }
        elseif ($_ -ne $args -and $_ -notmatch '[\\/]') {
            Microsoft.PowerShell.Utility\Set-Alias $_ $args -Force -ErrorAction Ignore
        }
    }
    $Matches = $null
}
else {
    Microsoft.PowerShell.Utility\Set-Alias psc PSCompletions -Force -ErrorAction Ignore
}

if (Test-Path -LiteralPath $PSCompletions.path.module_update) {
    $PSCompletions.new_version = (Get-Content -Raw $PSCompletions.path.module_update).Trim()
    $PSCompletions.version_list = $PSCompletions.new_version, $PSCompletions.version | Sort-Object { [version] $_ } -Descending -ErrorAction Ignore
    if ($PSCompletions.new_version -ne $PSCompletions.version) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update))
    }
    else {
        Remove-Item $PSCompletions.path.module_update -Force -ErrorAction SilentlyContinue
    }
}
else {
    if ($PSCompletions.update -or $PSCompletions.change) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.update_info))
    }
}

$PSCompletions.start_job()
