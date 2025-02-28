Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_list_first {
    param([array]$filter_list)
    if ($filter_list.Count -ge 1000) {
        $PSCompletions.menu.filter_list = $PSCompletions.handle_data_by_runspace($filter_list, {
                param ($items, $PSCompletions, $Host_UI)

                if ($PSCompletions.root_cmd -ne $null) {
                    $json = $PSCompletions.completions.$($PSCompletions.root_cmd)
                    $info = $json.info
                }
                $return = @()

                if ($PSCompletions.menu.is_show_tip) {
                    function Get-MultilineTruncatedString {
                        param ([string]$inputString, $Host_UI = $Host.UI)

                        $lineWidth = $Host_UI.RawUI.BufferSize.Width

                        if ($PSCompletions.config.enable_tip_follow_cursor -eq 1) {
                            $lineWidth -= $Host_UI.RawUI.CursorPosition.X
                        }

                        $currentWidth = 0
                        $outputString = ''
                        $currentLine = ''

                        $char_record = @{}

                        foreach ($char in $inputString.ToCharArray()) {
                            if ($char_record.ContainsKey($char)) {
                                $charWidth = $char_record[$char]
                            }
                            else {
                                $charWidth = $Host_UI.RawUI.NewBufferCellArray($char, $Host_UI.RawUI.BackgroundColor, $Host_UI.RawUI.BackgroundColor).LongLength
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

                        return $outputString
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
                    foreach ($item in $items) {
                        $tip_arr = @()
                        if ($item.ToolTip -ne $null) {
                            $tip = _replace $item.ToolTip
                            foreach ($v in ($tip -split "`n")) {
                                $tip_arr += (Get-MultilineTruncatedString $v $Host_UI) -split "`n"
                            }
                        }
                        $return += @{
                            ListItemText   = $item.ListItemText
                            CompletionText = $item.CompletionText
                            ToolTip        = $tip_arr
                        }
                    }
                }
                else {
                    $return += $items
                }
                return $return
            }, {
                param($results)
                $return = @()
                if ($PSCompletions.menu.is_show_tip) {
                    foreach ($result in $results) {
                        if ($result.ListItemText -eq '') {
                            continue
                        }
                        $PSCompletions.menu.tip_max_height = [Math]::Max($PSCompletions.menu.tip_max_height, $result.ToolTip.Count)
                        $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($result.ListItemText))
                        $return += @{
                            ListItemText   = $result.ListItemText
                            CompletionText = $result.CompletionText
                            ToolTip        = $result.ToolTip
                        }
                    }
                }
                else {
                    foreach ($result in $results) {
                        if ($result.ListItemText -eq '') {
                            continue
                        }
                        $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($result.ListItemText))
                        $return += @{
                            ListItemText   = $result.ListItemText
                            CompletionText = $result.CompletionText
                            ToolTip        = $result.ToolTip
                        }
                    }
                }
                return $return
            })
    }
    else {
        function Get-MultilineTruncatedString {
            param ([string]$inputString, $Host_UI = $Host.UI)

            $lineWidth = $Host_UI.RawUI.BufferSize.Width

            if ($PSCompletions.config.enable_tip_follow_cursor -eq 1) {
                $lineWidth -= $Host_UI.RawUI.CursorPosition.X
            }

            $currentWidth = 0
            $outputString = ''
            $currentLine = ''

            $char_record = @{}

            foreach ($char in $inputString.ToCharArray()) {
                if ($char_record.ContainsKey($char)) {
                    $charWidth = $char_record[$char]
                }
                else {
                    $charWidth = $Host_UI.RawUI.NewBufferCellArray($char, $Host_UI.RawUI.BackgroundColor, $Host_UI.RawUI.BackgroundColor).LongLength
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

            return $outputString
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

        $json = $PSCompletions.completions.$($PSCompletions.root_cmd)
        $info = $json.info
        $results = @()

        if ($PSCompletions.menu.is_show_tip) {
            foreach ($item in $filter_list) {
                if ($item.ListItemText -eq '') {
                    continue
                }
                $tip_arr = @()
                if ($item.ToolTip -ne $null) {
                    $tip = _replace $item.ToolTip
                    foreach ($v in ($tip -split "`n")) {
                        $tip_arr += (Get-MultilineTruncatedString $v $Host.UI) -split "`n"
                    }
                }
                $PSCompletions.menu.tip_max_height = [Math]::Max($PSCompletions.menu.tip_max_height, $tip_arr.Count)
                $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($item.ListItemText))
                $results += @{
                    ListItemText   = $item.ListItemText
                    CompletionText = $item.CompletionText
                    ToolTip        = $tip_arr
                }
            }
        }
        else {
            foreach ($item in $filter_list) {
                if ($item.ListItemText -eq '') {
                    continue
                }
                $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($item.ListItemText))
                $results += @{
                    ListItemText   = $item.ListItemText
                    CompletionText = $item.CompletionText
                }
            }
        }
        $PSCompletions.menu.filter_list = $results
    }
    $PSCompletions.menu.origin_filter_list = $PSCompletions.menu.filter_list.Clone()
    $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.config.list_min_width)
    $PSCompletions.menu.ui_size.Width = $PSCompletions.menu.list_max_width + 2 + $PSCompletions.menu.config.width_from_menu_left_to_item + $PSCompletions.menu.config.width_from_menu_right_to_item
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod parse_list {
    # X
    if ($PSCompletions.config.enable_list_follow_cursor -eq 1) {
        $PSCompletions.menu.pos.X = $Host.UI.RawUI.CursorPosition.X
        # 如果跟随鼠标，且超过右侧边界，则向左偏移
        $PSCompletions.menu.pos.X = [Math]::Min($PSCompletions.menu.pos.X, $Host.UI.RawUI.BufferSize.Width - 1 - $PSCompletions.menu.ui_size.Width)
    }
    else {
        $PSCompletions.menu.pos.X = 0
    }

    if ($PSCompletions.config.enable_tip_follow_cursor -eq 1) {
        $PSCompletions.menu.pos_tip.X = $PSCompletions.menu.pos.X
    }
    else {
        $PSCompletions.menu.pos_tip.X = 0
    }

    # Y
    $PSCompletions.menu.ui_size.Height = $PSCompletions.menu.filter_list.Count + 2
    if ($PSCompletions.menu.is_show_above) {
        if ($PSCompletions.config.list_max_count_when_above -eq -1) {
            $PSCompletions.menu.ui_size.Height = [Math]::Min($PSCompletions.menu.cursor_to_top, $PSCompletions.menu.ui_size.Height)

            $menu_limit = 4
            # 8: 2个补全项 + 3行提示的高度
            $rest = [Math]::Max(0, $PSCompletions.menu.cursor_to_top - 8)
            if ($rest -le 1) {
                $menu_limit += $rest + ($PSCompletions.menu.cursor_to_top -gt 4)
            }
            else {
                $r = $rest / 2
                if ($r -gt $PSCompletions.menu.tip_max_height) {
                    $menu_limit += $rest - $PSCompletions.menu.tip_max_height
                }
                else {
                    $menu_limit += $r
                }
            }
            if ($PSCompletions.menu.cursor_to_top -eq 6) {
                $menu_limit = 4
            }
        }
        else {
            $PSCompletions.menu.ui_size.Height = [Math]::Min($PSCompletions.menu.cursor_to_top, $PSCompletions.config.list_max_count_when_above + 2)
        }
    }
    else {
        if ($PSCompletions.config.list_max_count_when_below -eq -1) {
            $PSCompletions.menu.ui_size.Height = [Math]::Min($PSCompletions.menu.cursor_to_bottom, $PSCompletions.menu.ui_size.Height)

            $menu_limit = 4
            # 8: 2个补全项 + 3行提示的高度
            $rest = [Math]::Max(0, $PSCompletions.menu.cursor_to_bottom - 8)
            if ($rest -le 1) {
                $menu_limit += $rest + ($PSCompletions.menu.cursor_to_bottom -gt 4)
                $PSCompletions.menu.tip_max_height = $PSCompletions.menu.cursor_to_bottom - $menu_limit - 1
                if ($PSCompletions.menu.tip_max_height -lt 1) {
                    $PSCompletions.menu.tip_max_height = 1
                }
            }
            else {
                $r = $rest / 2
                if ($r -gt $PSCompletions.menu.tip_max_height) {
                    $menu_limit += $rest - $PSCompletions.menu.tip_max_height
                }
                else {
                    $menu_limit += $r
                }
            }
            if ($PSCompletions.menu.cursor_to_bottom -eq 6) {
                $menu_limit = 4
            }
        }
        else {
            $PSCompletions.menu.ui_size.Height = [Math]::Min($PSCompletions.menu.cursor_to_bottom, $PSCompletions.config.list_max_count_when_below + 2)
        }
    }

    if ($PSCompletions.menu.is_show_tip) {
        $menu_limit = [Math]::Min($menu_limit, $PSCompletions.menu.ui_size.Height)
        if ($PSCompletions.menu.is_show_above) {
            if ($menu_limit -gt 12 -and ($PSCompletions.menu.cursor_to_top - $menu_limit) -lt $PSCompletions.menu.tip_max_height) {
                $menu_limit = 12
                $PSCompletions.menu.tip_max_height = $PSCompletions.menu.cursor_to_top - $menu_limit - 1
            }
            else {
                # tip 可以显示的高度
                $rest = $PSCompletions.menu.cursor_to_top - $menu_limit - 1
                if ($PSCompletions.menu.tip_max_height -gt $rest) {
                    $PSCompletions.menu.tip_max_height = [Math]::Max(1, $rest)
                }
            }
            $PSCompletions.menu.ui_size.Height = [Math]::Min($menu_limit, $PSCompletions.menu.ui_size.Height)
            $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.menu.ui_size.Height - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above
            $PSCompletions.menu.pos_tip.Y = $PSCompletions.menu.pos.Y - $PSCompletions.menu.tip_max_height - 1
            if ($PSCompletions.menu.pos_tip.Y -lt 0) {
                $PSCompletions.menu.is_show_tip = $false
            }
        }
        else {
            if ($menu_limit -gt 12 -and ($PSCompletions.menu.cursor_to_bottom - $menu_limit) -lt $PSCompletions.menu.tip_max_height) {
                $menu_limit = 12
            }
            $PSCompletions.menu.ui_size.Height = [Math]::Min($menu_limit, $PSCompletions.menu.ui_size.Height)
            $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y + 1
            $PSCompletions.menu.pos_tip.Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_size.Height + 1
            if ($PSCompletions.menu.pos_tip.Y -gt $Host.UI.RawUI.BufferSize.Height - 1) {
                $PSCompletions.menu.is_show_tip = $false
            }
        }
    }
    else {
        if ($PSCompletions.menu.is_show_above) {
            $PSCompletions.menu.ui_size.Height = [Math]::Min($PSCompletions.menu.cursor_to_top, $PSCompletions.menu.ui_size.Height)
            $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.menu.ui_size.Height - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above
        }
        else {
            $PSCompletions.menu.ui_size.Height = [Math]::Min($PSCompletions.menu.cursor_to_bottom, $PSCompletions.menu.ui_size.Height)
            $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y + 1
        }
    }
    $PSCompletions.menu.page_max_index = $PSCompletions.menu.ui_size.Height - 3
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_buffer {
    param($startPos, $endPos)
    $top = New-Object System.Management.Automation.Host.Coordinates $startPos.X, $startPos.Y
    $bottom = New-Object System.Management.Automation.Host.Coordinates $endPos.X , $endPos.Y
    $buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $top, $bottom))
    @{
        top    = $top
        bottom = $bottom
        buffer = $buffer
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_pos {
    if ($PSCompletions.menu.is_show_above) {
        $menu_start_pos = @{
            X = $Host.UI.RawUI.WindowPosition.X
            Y = 0
        }
        $menu_end_pos = @{
            X = $PSCompletions.menu.pos.X + $PSCompletions.menu.ui_size.Width
            Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above
        }
        $menu_start_pos.Y = [Math]::Max($menu_start_pos.Y, $PSCompletions.menu.pos.Y)
    }
    else {
        $menu_start_pos = $PSCompletions.menu.pos
        $menu_end_pos = @{
            X = $menu_start_pos.X + $PSCompletions.menu.ui_size.Width
            Y = $menu_start_pos.Y + $PSCompletions.menu.ui_size.Height
        }
        $menu_end_pos.Y = [Math]::Min($menu_end_pos.Y, $Host.UI.RawUI.BufferSize.Height - 1)
    }
    if ($PSCompletions.menu.is_show_tip) {
        $tip_start_pos = @{
            X = $Host.UI.RawUI.WindowPosition.X
            Y = $PSCompletions.menu.pos.Y - $PSCompletions.menu.tip_max_height - 1
        }
        if ($PSCompletions.menu.is_show_above) {
            $tip_start_pos.Y = [Math]::Min($tip_start_pos.Y, $Host.UI.RawUI.WindowPosition.Y)
            $tip_end_pos = @{
                X = $Host.UI.RawUI.BufferSize.Width
                Y = $PSCompletions.menu.pos.Y
            }
        }
        else {
            $tip_start_pos.Y = $PSCompletions.menu.pos_tip.Y
            $tip_end_pos = @{
                X = $Host.UI.RawUI.BufferSize.Width
                Y = $PSCompletions.menu.pos_tip.Y + $PSCompletions.menu.tip_max_height + 1
            }
            $tip_end_pos.Y = [Math]::Min($tip_end_pos.Y, $Host.UI.RawUI.BufferSize.Height - 1)
        }
    }
    @{
        menu = @{
            start_pos = $menu_start_pos
            end_pos   = $menu_end_pos
        }
        tip  = @{
            start_pos = $tip_start_pos
            end_pos   = $tip_end_pos
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_cover_buffer {
    if (!$PSCompletions.is_show_tip) {
        return
    }
    if ($PSCompletions.config.enable_tip_cover_buffer -eq 1) {
        $box = @()
        $line = ' ' * $Host.UI.RawUI.BufferSize.Width
        if ($PSCompletions.menu.is_show_above) {
            foreach ($_ in 0..($PSCompletions.menu.pos.Y - 2)) {
                $box += $line
            }
            $pos = $Host.UI.RawUI.WindowPosition
        }
        else {
            foreach ($_ in 0..($Host.UI.RawUI.BufferSize.Height - $PSCompletions.menu.pos_tip.Y)) {
                $box += $line
            }
            $pos = @{
                X = 0
                Y = $PSCompletions.menu.pos_tip.Y - 1
            }
            $pos.Y = [Math]::Min($pos.Y, $Host.UI.RawUI.BufferSize.Height - 1)
        }
        $Host.UI.RawUI.SetBufferContents($pos, $Host.UI.RawUI.NewBufferCellArray($box, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor))
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_buffer {
    # XXX: 在 Windows PowerShell 5.x 中，始终覆盖菜单缓冲区，以处理兼容性问题
    if ($PSCompletions.config.enable_list_cover_buffer -eq 1 -or $PSEdition -ne 'Core') {
        $box = @()
        $line = ' ' * $Host.UI.RawUI.BufferSize.Width
        foreach ($_ in 0..$PSCompletions.menu.ui_size.Height) {
            $box += $line
        }
        $pos = @{
            X = 0
            Y = $PSCompletions.menu.pos.Y
        }
        if ($PSCompletions.menu.is_show_above) { $pos.Y -- }
        $Host.UI.RawUI.SetBufferContents($pos, $Host.UI.RawUI.NewBufferCellArray($box, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor))
    }

    # XXX: 在 Windows PowerShell 5.x 中，边框使用以下符号以处理兼容性问题
    if ($PSEdition -ne 'Core') {
        $horizontal = '-'
        $vertical = '|'
        $top_left = '+'
        $bottom_left = '+'
        $top_right = '+'
        $bottom_right = '+'
    }
    else {
        $horizontal = $PSCompletions.config.horizontal
        $vertical = $PSCompletions.config.vertical
        $top_left = $PSCompletions.config.top_left
        $bottom_left = $PSCompletions.config.bottom_left
        $top_right = $PSCompletions.config.top_right
        $bottom_right = $PSCompletions.config.bottom_right
    }

    $border_box = @()
    $content_box = @()

    $border_box += [string]$top_left + $horizontal * ($PSCompletions.menu.list_max_width + $PSCompletions.config.width_from_menu_left_to_item + $PSCompletions.config.width_from_menu_right_to_item) + $top_right

    $line = [string]$vertical + (' ' * ($PSCompletions.config.width_from_menu_left_to_item + $PSCompletions.menu.list_max_width + $PSCompletions.config.width_from_menu_right_to_item)) + [string]$vertical
    $left = ' ' * $PSCompletions.config.width_from_menu_left_to_item
    $right = ' ' * $PSCompletions.config.width_from_menu_right_to_item
    foreach ($_ in 0..($PSCompletions.menu.ui_size.Height - 3)) {
        $content_length = $PSCompletions.menu.get_length($PSCompletions.menu.filter_list[$_].ListItemText)
        $content = $PSCompletions.menu.filter_list[$_].ListItemText + ' ' * ($PSCompletions.menu.list_max_width - $content_length)
        $border_box += $line
        $content_box += $left + $content + $right
    }

    $status = "$(([string]($PSCompletions.menu.selected_index + 1)).PadLeft($PSCompletions.menu.filter_list.Count.ToString().Length, ' '))"

    $border_box += [string]$bottom_left + $horizontal * 2 + ' ' * ($status.Length + 1) + $horizontal * ($PSCompletions.menu.list_max_width + $PSCompletions.config.width_from_menu_left_to_item + $PSCompletions.config.width_from_menu_right_to_item - $status.Length - 3) + $bottom_right

    $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.pos, $Host.UI.RawUI.NewBufferCellArray($border_box, $PSCompletions.config.border_text, $PSCompletions.config.border_back))

    $Host.UI.RawUI.SetBufferContents(@{
            X = $PSCompletions.menu.pos.X + 1
            Y = $PSCompletions.menu.pos.Y + 1
        }, $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.item_text, $PSCompletions.config.item_back))
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_list_buffer {
    param([int]$offset)
    $content_box = @()
    $left = ' ' * $PSCompletions.config.width_from_menu_left_to_item
    $right = ' ' * $PSCompletions.config.width_from_menu_right_to_item
    foreach ($_ in $offset..($PSCompletions.menu.ui_size.Height - 3 + $offset)) {
        $content_length = $PSCompletions.menu.get_length($PSCompletions.menu.filter_list[$_].ListItemText)
        $content = $PSCompletions.menu.filter_list[$_].ListItemText + ' ' * ($PSCompletions.menu.list_max_width - $content_length)
        $content_box += $left + $content + $right
    }
    $pos = @{
        X = $PSCompletions.menu.pos.X + 1
        Y = $PSCompletions.menu.pos.Y + 1
    }
    $Host.UI.RawUI.SetBufferContents($pos, $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.item_text, $PSCompletions.config.item_back))
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_filter_buffer {
    param([string]$filter)
    if ($PSCompletions.menu.old_filter_buffer) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_filter_pos, $PSCompletions.menu.old_filter_buffer)
    }
    $X = $PSCompletions.menu.pos.X
    $Y = $PSCompletions.menu.pos.Y

    $old_top = New-Object System.Management.Automation.Host.Coordinates $X, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.ui.RawUI.BufferSize.Width, $Y

    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))

    $PSCompletions.menu.old_filter_buffer = $old_buffer  # 之前的内容
    $PSCompletions.menu.old_filter_pos = $old_top  # 之前的位置

    $char = $PSCompletions.config.filter_symbol
    $middle = [System.Math]::Ceiling($char.Length / 2)
    $start = $char.Substring(0, $middle)
    $end = $char.Substring($middle)

    $buffer_filter = $Host.UI.RawUI.NewBufferCellArray(@(@($start, $filter, $end) -join ''), $PSCompletions.config.filter_text, $PSCompletions.config.filter_back)
    $pos_filter = $Host.UI.RawUI.CursorPosition
    $pos_filter.X = $PSCompletions.menu.pos.X + 2
    $pos_filter.Y = $PSCompletions.menu.pos.Y
    $Host.UI.RawUI.SetBufferContents($pos_filter, $buffer_filter)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_status_buffer {
    if ($PSCompletions.menu.old_status_buffer) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_status_pos, $PSCompletions.menu.old_status_buffer)
    }
    $X = $PSCompletions.menu.pos.X + 3
    if ($PSCompletions.menu.is_show_above) {
        $Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above
    }
    else {
        $Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_size.Height - 1
    }

    $old_top = New-Object System.Management.Automation.Host.Coordinates $X, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.UI.RawUI.BufferSize.Width, $Y

    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))

    $PSCompletions.menu.old_status_buffer = $old_buffer  # 之前的内容
    $PSCompletions.menu.old_status_pos = $old_top  # 之前的位置

    $current = "$(([string]($PSCompletions.menu.selected_index + 1)).PadLeft($PSCompletions.menu.filter_list.Count.ToString().Length, ' '))"
    $buffer_status = $Host.UI.RawUI.NewBufferCellArray(@("$current$($PSCompletions.config.status_symbol)$($PSCompletions.menu.filter_list.Count)"), $PSCompletions.config.status_text, $PSCompletions.config.status_back)

    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $buffer_status)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_old_tip_buffer {
    param([int]$X, [int]$Y)
    if ($PSCompletions.config.enable_tip_cover_buffer -eq 1) {
        if ($PSCompletions.menu.is_show_above) {
            $Y = 0
            $to_Y = $PSCompletions.menu.pos.Y
        }
        else {
            $Y = $PSCompletions.menu.pos_tip.Y - 1
            $to_Y = $Host.UI.RawUI.BufferSize.Height - 1
        }
    }
    else {
        $Y = $PSCompletions.menu.pos_tip.Y - 1
        if ($PSCompletions.menu.is_show_above) {
            $to_Y = $PSCompletions.menu.pos.Y
        }
        else {
            $to_Y = $PSCompletions.menu.pos_tip.Y + $PSCompletions.menu.tip_max_height
        }
    }
    $PSCompletions.menu.old_tip_buffer = $PSCompletions.menu.get_buffer(@{ X = 0; Y = $Y }, @{ X = $Host.UI.RawUI.BufferSize.Width; Y = $to_Y })
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_tip_buffer {
    param([int]$index)
    $box = @()
    $line = ' ' * $Host.UI.RawUI.BufferSize.Width
    if ($PSCompletions.config.enable_tip_cover_buffer -eq 1) {
        if ($PSCompletions.menu.is_show_above) {
            foreach ($_ in 0..($PSCompletions.menu.pos.Y - 1)) {
                $box += $line
            }
            $pos = @{
                X = 0
                Y = 0
            }
        }
        else {
            foreach ($_ in 0..($Host.UI.RawUI.BufferSize.Height - $PSCompletions.menu.pos_tip.Y)) {
                $box += $line
            }
            $pos = @{
                X = 0
                Y = $PSCompletions.menu.pos_tip.Y - 1
            }
        }
    }
    else {
        foreach ($_ in 0..($PSCompletions.menu.tip_max_height + 1)) {
            $box += $line
        }
        $pos = @{
            X = 0
            Y = $PSCompletions.menu.pos_tip.Y - 1
        }
        if ($PSCompletions.menu.is_show_above) {
            $pos.Y = [Math]::Max($pos.Y, 0)
        }
    }
    $Host.UI.RawUI.SetBufferContents($pos, $Host.UI.RawUI.NewBufferCellArray($box, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor))

    if ($PSCompletions.menu.filter_list[$index].ToolTip -ne $null) {
        $pos = @{
            X = $PSCompletions.menu.pos_tip.X
            Y = $PSCompletions.menu.pos_tip.Y
        }
        $tip = $PSCompletions.menu.filter_list[$index].ToolTip
        if ($PSCompletions.menu.tip_max_height -eq 1) {
            if ($tip.Count -gt 1) {
                $tip = $tip[0]
            }
        }
        else {
            if ($tip.Count -gt $PSCompletions.menu.tip_max_height) {
                $tip = $tip[0..($PSCompletions.menu.tip_max_height - 1)]
            }
        }
        $Host.UI.RawUI.SetBufferContents($pos, $Host.UI.RawUI.NewBufferCellArray($tip, $PSCompletions.config.tip_text, $PSCompletions.config.tip_back))
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_selection {
    if ($PSCompletions.menu.old_selection) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_selection.pos, $PSCompletions.menu.old_selection.buffer)
    }

    $X = $PSCompletions.menu.pos.X + 1
    $to_X = $X + $PSCompletions.menu.list_max_width - 1
    # 如果选中高亮需要包含 margin
    if ($PSCompletions.config.enable_selection_with_margin -eq 1) {
        $to_X += $PSCompletions.config.width_from_menu_left_to_item + $PSCompletions.config.width_from_menu_right_to_item
    }
    else {
        $X += $PSCompletions.config.width_from_menu_left_to_item
    }

    # 当前页的第几个
    $Y = $PSCompletions.menu.pos.Y + 1 + $PSCompletions.menu.page_current_index

    # 根据坐标，生成需要被改变内容的矩形，也就是要被选中的项
    $Rectangle = New-Object System.Management.Automation.Host.Rectangle $X, $Y, $to_X, $Y

    # 通过矩形，获取到这个矩形中的原本的内容
    $LineBuffer = $Host.UI.RawUI.GetBufferContents($Rectangle)
    $PSCompletions.menu.old_selection = @{
        pos    = @{
            X = $X
            Y = $Y
        }
        buffer = $LineBuffer
    }
    # 给原本的内容设置颜色和背景颜色
    # XXX: 对于多字节字符，需要过滤掉 Trailing 类型字符以确保正确渲染
    # $content = foreach ($i in $LineBuffer) { $i.Character }
    $content = foreach ($i in $LineBuffer.Where({ $_.BufferCellType -ne 'Trailing' })) { $i.Character }
    $LineBuffer = $Host.UI.RawUI.NewBufferCellArray(
        @([string]::Join('', $content)),
        $PSCompletions.config.selected_text,
        $PSCompletions.config.selected_back
    )
    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $LineBuffer)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod move_selection {
    param([bool]$isDown)

    $moveDirection = if ($isDown) { 1 } else { -1 }

    $is_move = if ($isDown) {
        $PSCompletions.menu.page_current_index -lt $PSCompletions.menu.page_max_index
    }
    else {
        $PSCompletions.menu.page_current_index -gt 0
    }

    $new_selected_index = $PSCompletions.menu.selected_index + $moveDirection

    if ($PSCompletions.config.enable_list_loop -eq 1) {
        $PSCompletions.menu.selected_index = ($new_selected_index + $PSCompletions.menu.filter_list.Count) % $PSCompletions.menu.filter_list.Count
    }
    else {
        # Handle no loop
        $PSCompletions.menu.selected_index = if ($new_selected_index -lt 0) {
            0
        }
        elseif ($new_selected_index -ge $PSCompletions.menu.filter_list.Count) {
            $PSCompletions.menu.filter_list.Count - 1
        }
        else {
            $new_selected_index
        }
    }

    if ($is_move) {
        $PSCompletions.menu.page_current_index = ($PSCompletions.menu.page_current_index + $moveDirection) % ($PSCompletions.menu.page_max_index + 1)
        if ($PSCompletions.menu.page_current_index -lt 0) {
            $PSCompletions.menu.page_current_index += $PSCompletions.menu.page_max_index + 1
        }
    }
    elseif ($PSCompletions.config.enable_list_loop -eq 1 -or ($new_selected_index -ge 0 -and $new_selected_index -lt $PSCompletions.menu.filter_list.Count)) {
        if (!$isDown -and $PSCompletions.menu.selected_index -eq $PSCompletions.menu.filter_list.Count - 1) {
            $PSCompletions.menu.page_current_index += $PSCompletions.menu.page_max_index
        }
        elseif ($isDown -and $PSCompletions.menu.selected_index -eq 0) {
            $PSCompletions.menu.page_current_index -= $PSCompletions.menu.page_max_index
        }

        $PSCompletions.menu.offset = ($PSCompletions.menu.offset + $moveDirection) % ($PSCompletions.menu.filter_list.Count - $PSCompletions.menu.page_max_index)
        if ($PSCompletions.menu.offset -lt 0) {
            $PSCompletions.menu.offset += $PSCompletions.menu.filter_list.Count - $PSCompletions.menu.page_max_index
        }

        $PSCompletions.menu.new_list_buffer($PSCompletions.menu.offset)
        $PSCompletions.menu.old_selection = $null
    }
    $PSCompletions.menu.set_selection()
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_prefix {
    $prefix = $PSCompletions.menu.filter_list[-1].CompletionText
    for ($i = $PSCompletions.menu.filter_list.count - 2; $i -ge 0 -and $prefix; --$i) {
        $text = $PSCompletions.menu.filter_list[$i].CompletionText
        if ($text -ne $null) {
            while ($prefix -and !$text.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $prefix = $prefix.Substring(0, $prefix.Length - 1)
            }
        }
    }
    $PSCompletions.menu.filter = $PSCompletions.menu.filter_by_auto_pick = $prefix
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod filter_completions {
    param([array]$filter_list)
    # 如果是前缀匹配
    if ($PSCompletions.config.enable_prefix_match_in_filter -eq 1) {
        $match = "$([WildcardPattern]::Escape($PSCompletions.menu.filter))*"
    }
    else {
        $match = "*$([WildcardPattern]::Escape($PSCompletions.menu.filter))*"
    }
    $PSCompletions.menu.filter_list = @()

    foreach ($f in $filter_list) {
        if ($f.CompletionText -and $f.CompletionText -like $match) {
            $PSCompletions.menu.filter_list += $f
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod reset {
    param(
        [bool]$clearAll = $true,
        [bool]$clearMenu = $true
    )

    if ($PSCompletions.menu.old_tip_buffer) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_tip_buffer.top, $PSCompletions.menu.old_tip_buffer.buffer)
    }

    if ($clearMenu -and $PSCompletions.menu.old_menu_buffer) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_menu_buffer.top, $PSCompletions.menu.old_menu_buffer.buffer)
    }

    if ($clearAll) {
        $PSCompletions.menu.old_tip_buffer = $null
        $PSCompletions.menu.old_menu_buffer = $null
        if ($PSCompletions.menu.origin_menu_buffer) {
            $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.origin_menu_buffer.top, $PSCompletions.menu.origin_menu_buffer.buffer)
            $PSCompletions.menu.origin_menu_buffer = $null
        }
        if ($PSCompletions.menu.origin_tip_buffer) {
            $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.origin_tip_buffer.top, $PSCompletions.menu.origin_tip_buffer.buffer)
            $PSCompletions.menu.origin_tip_buffer = $null
        }
    }
    $PSCompletions.menu.old_selection = $null
    $PSCompletions.menu.old_filter_buffer = $null
    $PSCompletions.menu.old_filter_pos = $null
    $PSCompletions.menu.old_status_buffer = $null
    $PSCompletions.menu.old_status_pos = $null

    $PSCompletions.menu.offset = 0
    $PSCompletions.menu.selected_index = 0
    $PSCompletions.menu.page_current_index = 0

    if ($PSCompletions.menu.by_TabExpansion2) {
        $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip_when_enhance -eq 1
    }
    else {
        $enable_tip = $PSCompletions.config.comp_config.$($PSCompletions.root_cmd).enable_tip
        if ($enable_tip -ne $null) {
            $PSCompletions.menu.is_show_tip = $enable_tip -eq 1 -and !$PSCompletions.menu.ignore_tip
        }
        else {
            $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip -eq 1 -and !$PSCompletions.menu.ignore_tip
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
    param($filter_list)
    if ($Host.UI.RawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        ''
        return
    }
    if (!$filter_list) { return }
    function handleOutput($item) {
        $out = $item.CompletionText
        try {
            if ((Get-ItemProperty ($item.ToolTip)).Attributes -like '*Directory*') {
                if ($out[-1] -match "^['`"]$") {
                    if ($out[-2] -match "^[/\\]$") {
                        return $out
                    }
                    return $out.Insert($out.Length - 1, $PSCompletions.separator)
                }
                if ($out[-1] -match "^[/\\]$") {
                    return $out
                }
                return $out + $PSCompletions.separator
            }
        }
        catch {}
        return $out
    }

    $PSCompletions.menu.pos = @{ X = 0; Y = 0 }
    $PSCompletions.menu.pos_tip = @{ X = 0; Y = 0 }

    $PSCompletions.menu.list_max_width = $PSCompletions.config.list_min_width
    $PSCompletions.menu.tip_max_height = 1
    $PSCompletions.menu.ui_size = $Host.UI.RawUI.BufferSize

    $PSCompletions.menu.filter = ''  # 过滤的关键词
    $PSCompletions.menu.old_filter = ''

    $PSCompletions.menu.page_current_index = 0 # 当前显示页中的索引

    $PSCompletions.menu.selected_index = 0  # 当前选中项的实际索引
    $PSCompletions.menu.old_selected_index = 0

    $PSCompletions.menu.offset = 0  # 索引的偏移量，用于滚动翻页

    $PSCompletions.menu.reset()

    $PSCompletions.menu.handle_list_first($filter_list)

    if ($PSCompletions.config.enable_enter_when_single -eq 1 -and $PSCompletions.menu.filter_list.Count -eq 1) {
        return handleOutput $PSCompletions.menu.filter_list[0]
    }

    $current_encoding = [console]::OutputEncoding
    [console]::OutputEncoding = $PSCompletions.encoding

    $PSCompletions.menu.cursor_to_bottom = $Host.UI.RawUI.BufferSize.Height - 1 - $Host.UI.RawUI.CursorPosition.Y
    $PSCompletions.menu.cursor_to_top = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above - 1

    $PSCompletions.menu.is_show_above = $PSCompletions.menu.cursor_to_bottom -lt $PSCompletions.menu.cursor_to_top

    $PSCompletions.menu.parse_list()

    # 如果解析后的菜单高度小于 3 (上下边框 + 1个补全项)
    if ($PSCompletions.menu.ui_size.Height -lt 3 -or $PSCompletions.menu.ui_size.Width -gt $Host.ui.RawUI.BufferSize.Width - 2) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        ''
        return
    }

    # 显示菜单之前，记录 buffer
    $pos = $PSCompletions.menu.get_pos()
    $PSCompletions.menu.origin_menu_buffer = $PSCompletions.menu.get_buffer($pos.menu.start_pos, $pos.menu.end_pos)

    $PSCompletions.menu.origin_tip_buffer = $PSCompletions.menu.get_buffer($pos.tip.start_pos, $pos.tip.end_pos)

    $PSCompletions.menu.old_menu_buffer = $PSCompletions.menu.get_buffer(
        @{
            X = $Host.UI.RawUI.WindowPosition.X
            Y = $PSCompletions.menu.pos.Y
        },
        @{
            X = $Host.ui.RawUI.BufferSize.Width
            Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_size.Height - $PSCompletions.menu.is_show_above
        }
    )

    if ($PSCompletions.menu.is_show_tip) { $PSCompletions.menu.get_old_tip_buffer($PSCompletions.menu.pos_tip.X, $PSCompletions.menu.pos_tip.Y) }
    # 显示菜单
    $PSCompletions.menu.new_buffer()
    if ($PSCompletions.menu.is_show_tip) { $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index) }
    if ($PSCompletions.config.enable_prefix_match_in_filter -eq 1) { $PSCompletions.menu.get_prefix() }
    $PSCompletions.menu.new_filter_buffer($PSCompletions.menu.filter)
    $PSCompletions.menu.new_status_buffer()
    $PSCompletions.menu.set_selection()
    $old_filter_list = $PSCompletions.menu.filter_list

    :loop while (($PressKey = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode) {
        $pressShift = 0x10 -band [int]$PressKey.ControlKeyState
        $pressCtrl = $PressKey.ControlKeyState -like '*CtrlPressed*'

        switch ($PressKey.VirtualKeyCode) {
            9 {
                # 9: Tab
                if ($PSCompletions.menu.filter_list.Count -eq 1) {
                    $PSCompletions.menu.reset()
                    $PSCompletions.menu.filter_list[$PSCompletions.menu.selected_index].CompletionText
                    break loop
                }
                $PSCompletions.menu.move_selection(!$pressShift)
                break
            }
            { $_ -eq 27 -or ($pressCtrl -and $_ -eq 67) } {
                # 27: ESC
                # 67: Ctrl + c
                $PSCompletions.menu.reset()
                $PSCompletions.menu.temp = @{}
                ''
                break loop
            }
            { $_ -in @(32, 13) } {
                # 32: Space
                # 13: Enter
                handleOutput $PSCompletions.menu.filter_list[$PSCompletions.menu.selected_index]
                $PSCompletions.menu.reset()
                break loop
            }

            # 向上
            # 37: Up
            # 38: Left
            # 85: Ctrl + u
            # 80: Ctrl + p
            { $_ -in @(37, 38) -or ($pressCtrl -and ($_ -eq 85 -or $_ -eq 80)) } {
                $PSCompletions.menu.move_selection($false)
                break
            }
            # 向下
            # 39: Right
            # 40: Down
            # 68: Ctrl + d
            # 78: Ctrl + n
            { $_ -in @(39, 40) -or ($pressCtrl -and ($_ -eq 68 -or $_ -eq 78)) } {
                $PSCompletions.menu.move_selection($true)
                break
            }
            # Character/Backspace
            { $PressKey.Character } {
                # update filter
                if ($PressKey.Character -eq 8) {
                    # 8: backspace
                    if ($PSCompletions.menu.filter -eq $PSCompletions.menu.filter_by_auto_pick) {
                        $PSCompletions.menu.filter = ''
                        $PSCompletions.menu.filter_by_auto_pick = ''
                        $PSCompletions.menu.reset()
                        ''
                        break loop
                    }
                    if ($PSCompletions.menu.filter) {
                        $PSCompletions.menu.filter = $PSCompletions.menu.filter.Substring(0, $PSCompletions.menu.filter.Length - 1)
                    }
                    else {
                        $PSCompletions.menu.reset()
                        ''
                        break loop
                    }
                    $PSCompletions.menu.new_cover_buffer()
                    $PSCompletions.menu.reset($false, $PSCompletions.menu.is_show_tip)
                    $PSCompletions.menu.filter_completions($PSCompletions.menu.origin_filter_list)
                    $PSCompletions.menu.parse_list()
                    $PSCompletions.menu.new_buffer()
                    if ($PSCompletions.menu.is_show_tip) { $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index) }
                    $PSCompletions.menu.new_status_buffer()
                    $PSCompletions.menu.set_selection(0)
                }
                else {
                    # add char
                    $PSCompletions.menu.filter += $PressKey.Character
                    $PSCompletions.menu.filter_completions($PSCompletions.menu.filter_list)
                    if (!$PSCompletions.menu.filter_list) {
                        $PSCompletions.menu.filter = $PSCompletions.menu.old_filter
                        $PSCompletions.menu.filter_list = $old_filter_list
                    }
                    else {
                        $PSCompletions.menu.new_cover_buffer()

                        # XXX: 处理补全项过滤时菜单消失后出现的背景闪烁问题
                        if (!$PSCompletions.menu.is_show_tip) {
                            if ($PSCompletions.menu.page_current_index -eq 0) {
                                $box = @(' ' * $PSCompletions.menu.list_max_width)
                                $Host.UI.RawUI.SetBufferContents(@{
                                        X = $PSCompletions.menu.pos.X + 1
                                        Y = $PSCompletions.menu.pos.Y + 1
                                    }, $Host.UI.RawUI.NewBufferCellArray($box, $PSCompletions.config.selected_text, $PSCompletions.config.selected_back))
                                $pos = @{
                                    X = $PSCompletions.menu.pos.X + 1
                                    Y = $PSCompletions.menu.pos.Y + 2
                                }
                            }
                            else {
                                $box = @()
                                $line = ' ' * $PSCompletions.menu.list_max_width
                                foreach ($l in $PSCompletions.menu.ui_size.Height - 2) {
                                    $box += $line
                                }
                                $pos = @{
                                    X = $PSCompletions.menu.pos.X + 1
                                    Y = $PSCompletions.menu.pos.Y + 1
                                }
                            }
                            $Host.UI.RawUI.SetBufferContents($pos, $Host.UI.RawUI.NewBufferCellArray($box, $PSCompletions.config.item_back, $PSCompletions.config.item_back))
                        }

                        $PSCompletions.menu.reset($false)
                        $PSCompletions.menu.parse_list()
                        $PSCompletions.menu.new_buffer()
                        if ($PSCompletions.menu.is_show_tip) { $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index) }
                        $PSCompletions.menu.new_status_buffer()
                        $PSCompletions.menu.set_selection(0)
                    }
                }
                break
            }
        }
        if ($PSCompletions.menu.selected_index -ne $PSCompletions.menu.old_selected_index) {
            $PSCompletions.menu.new_status_buffer()
            if ($PSCompletions.menu.is_show_tip) { $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index) }
            $PSCompletions.menu.old_selected_index = $PSCompletions.menu.selected_index
        }
        if ($PSCompletions.menu.filter -ne $PSCompletions.menu.old_filter) {
            $PSCompletions.menu.new_filter_buffer($PSCompletions.menu.filter)
            $PSCompletions.menu.old_filter = $PSCompletions.menu.filter
            $old_filter_list = $PSCompletions.menu.filter_list
        }
    }
    [console]::OutputEncoding = $current_encoding
    $PSCompletions.menu.ignore_tip = $false
}
