Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_list_first {
    param([array]$filter_list)
    $max_width = 0

    $PSCompletions.menu.ui_size.width = $PSCompletions.menu.list_max_width + 2 + $PSCompletions.menu.config.menu_list_margin_left + $PSCompletions.menu.config.menu_list_margin_right
    if ($PSCompletions.menu.is_show_tip) {
        $filterListTasks = @()
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
        $runspacePool.Open()

        $scriptBlock = {
            param ($items, $PSCompletions, $Host_UI)
            function Get-MultilineTruncatedString {
                param ([string]$inputString, $Host_UI = $Host.UI)

                # 指定一行的最大宽度
                $lineWidth = $Host_UI.RawUI.BufferSize.Width

                if ($PSCompletions.config.menu_tip_follow_cursor) {
                    $w = $lineWidth - $Host_UI.RawUI.CursorPosition.X
                    $lineWidth = [Math]::Max($w, $PSCompletions.menu.ui_size.Width)
                }
                $PSCompletions.menu.tip_width = $lineWidth

                # 初始化一些变量
                $currentWidth = 0
                $outputString = ""
                $currentLine = ""

                foreach ($char in $inputString.ToCharArray()) {
                    # 获取当前字符的宽度（1 或 2）
                    $charWidth = if ([System.Text.Encoding]::UTF8.GetByteCount($char) -eq 1) { 1 } else { 2 }

                    # 如果添加这个字符会超过最大宽度，就换行
                    if ($currentWidth + $charWidth -gt $lineWidth) {
                        # 添加当前行到输出字符串并换行
                        $outputString += $currentLine + "`n"
                        # 重置当前行和宽度
                        $currentLine = ""
                        $currentWidth = 0
                    }

                    # 添加字符到当前行，并更新当前宽度
                    $currentLine += $char
                    $currentWidth += $charWidth
                }

                # 添加最后一行到输出字符串
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

            if ($PSCompletions.current_cmd) {
                $json = $PSCompletions.completions.$($PSCompletions.current_cmd)
                $info = $json.info
            }
            foreach ($item in $items) {
                $tip_arr = @()
                if ($item.ToolTip) {
                    $tip = _replace $item.ToolTip
                    foreach ($v in ($tip -split "`n")) {
                        $tip_arr += (Get-MultilineTruncatedString $v $Host_UI) -split "`n"
                    }
                }
                @{
                    ListItemText   = $item.ListItemText
                    CompletionText = $item.CompletionText
                    ToolTip        = $tip_arr
                }
            }
        }

        foreach ($arr in $PSCompletions.split_array($filter_list, [Environment]::ProcessorCount, $true)) {
            $filterListTasks += [powershell]::Create().AddScript($scriptBlock).AddArgument($arr).AddArgument($PSCompletions).AddArgument($Host.UI)
        }

        $runspaces = foreach ($task in $filterListTasks) {
            $task.RunspacePool = $runspacePool
            $job = $task.BeginInvoke()
            @{ Runspace = $task; Job = $job }
        }

        foreach ($rs in $runspaces) {
            $results = $rs.Runspace.EndInvoke($rs.Job)
            $rs.Runspace.Dispose()
            foreach ($result in $results) {
                $PSCompletions.menu.tip_max_height = [Math]::Max($PSCompletions.menu.tip_max_height, $result.ToolTip.Count)
                $result = @{
                    ListItemText   = $result.ListItemText
                    CompletionText = $result.CompletionText
                    ToolTip        = $result.ToolTip
                }
                $PSCompletions.menu.origin_filter_list += $result
                $PSCompletions.menu.filter_list += $result
            }
        }
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
    else {
        $PSCompletions.menu.origin_filter_list = [array]$filter_list
        $PSCompletions.menu.filter_list = [array]$filter_list
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod parse_list {
    # X
    if ($PSCompletions.config.menu_list_follow_cursor) {
        $PSCompletions.menu.pos.X = $Host.UI.RawUI.CursorPosition.X
        # 如果跟随鼠标，且超过右侧边界，则向左偏移
        $PSCompletions.menu.pos.X = [Math]::Min($PSCompletions.menu.pos.X, $Host.UI.RawUI.BufferSize.Width - 1 - $PSCompletions.menu.ui_size.Width)
    }
    else {
        $PSCompletions.menu.pos.X = 0
    }

    # 当为 0 时，有几率出现渲染错误，所以坐标右移一点
    if ($PSCompletions.menu.pos.x -eq 0) { $PSCompletions.menu.pos.x ++ }

    if ($PSCompletions.config.menu_tip_follow_cursor) {
        $PSCompletions.menu.pos_tip.X = $PSCompletions.menu.pos.X
    }
    else {
        $PSCompletions.menu.pos_tip.X = 0
    }

    # Y
    $PSCompletions.menu.cursor_to_bottom = $Host.UI.RawUI.BufferSize.Height - $Host.UI.RawUI.CursorPosition.Y - 1
    $PSCompletions.menu.cursor_to_top = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.config.menu_above_margin_bottom - 1

    $PSCompletions.menu.is_show_above = if ($PSCompletions.menu.cursor_to_bottom -ge $PSCompletions.menu.cursor_to_top) { $false }else { $true }

    $PSCompletions.menu.ui_size.height = $PSCompletions.menu.filter_list.Count + 2
    if ($PSCompletions.menu.is_show_above) {
        if ($PScompletions.config.menu_above_list_max_count -ne -1) {
            $PSCompletions.menu.ui_size.height = [Math]::Min($PSCompletions.menu.ui_size.height, $PScompletions.config.menu_above_list_max_count + 2)
        }
        else {
            $PSCompletions.menu.ui_size.height = [Math]::Min($PSCompletions.menu.ui_size.height, $PSCompletions.menu.cursor_to_top)
        }
    }
    else {
        if ($PScompletions.config.menu_below_list_max_count -ne -1) {
            $PSCompletions.menu.ui_size.height = [Math]::Min($PSCompletions.menu.ui_size.height, $PScompletions.config.menu_below_list_max_count + 2)
        }
        else {
            $PSCompletions.menu.ui_size.height = [Math]::Min($PSCompletions.menu.ui_size.height, $PSCompletions.menu.cursor_to_bottom)
        }
    }
    if ($PSCompletions.menu.is_show_above) {
        $new_ui_height = $PSCompletions.menu.cursor_to_top - $PSCompletions.menu.tip_max_height - 1
        if ($new_ui_height -lt 3) {
            $PSCompletions.menu.is_show_tip = $false
        }
        else {
            $PSCompletions.menu.ui_size.height = [Math]::Min($new_ui_height, $PSCompletions.menu.filter_list.Count + 2)
        }
        $PSCompletions.menu.ui_size.height = [Math]::Max($PSCompletions.menu.ui_size.height, 3)
        $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.menu.ui_size.height - $PSCompletions.config.menu_above_margin_bottom
        # 设置 tip 的 起始位置
        $PSCompletions.menu.pos_tip.Y = $PSCompletions.menu.pos.Y - $PSCompletions.menu.tip_max_height - 1
        if ($PSCompletions.menu.pos_tip.Y -lt 0) {
            $PSCompletions.menu.is_show_tip = $false
        }
    }
    else {
        $new_ui_height = $PSCompletions.menu.cursor_to_bottom - $PSCompletions.menu.tip_max_height - 1
        if ($new_ui_height -lt 3) {
            $PSCompletions.menu.is_show_tip = $false
        }
        else {
            $PSCompletions.menu.ui_size.height = [Math]::Min($new_ui_height, $PSCompletions.menu.filter_list.Count + 2)
        }
        $PSCompletions.menu.ui_size.height = [Math]::Max($PSCompletions.menu.ui_size.height, 3)
        $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y + 1
        $PSCompletions.menu.pos_tip.Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_size.height + 1
        if ($PSCompletions.menu.pos_tip.Y -ge $Host.UI.RawUI.BufferSize.Height - 1) {
            $PSCompletions.menu.is_show_tip = $false
        }
    }
    $PSCompletions.menu.page_max_index = $PSCompletions.menu.ui_size.height - 3
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
            Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.menu_above_margin_bottom
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
            $tip_end_pos = @{
                X = $Host.UI.RawUI.BufferSize.Width
                Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.menu_above_margin_bottom
            }
            $tip_start_pos.Y = [Math]::Min($tip_start_pos.Y, $Host.UI.RawUI.WindowPosition.Y)
        }
        else {
            $tip_start_pos.Y = $PSCompletions.menu.pos.Y
            $tip_end_pos = @{
                X = $Host.UI.RawUI.BufferSize.Width
                Y = $tip_start_pos.Y + $PSCompletions.menu.ui_size.Height + $PSCompletions.menu.tip_max_height + 1
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
    if ($PSCompletions.config.menu_tip_cover_buffer) {
        $box = @()
        if ($PSCompletions.menu.is_show_above) {
            foreach ($_ in 0..($PSCompletions.menu.pos.Y - 2)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = $Host.UI.RawUI.WindowPosition
        }
        else {
            foreach ($_ in 0..($Host.UI.RawUI.BufferSize.Height - $PSCompletions.menu.pos_tip.Y)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = $PSCompletions.menu.pos_tip.Y - 1
            }
            $pos.Y = [Math]::Min($pos.Y, $Host.UI.RawUI.BufferSize.Height - 1)
        }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_buffer {
    if ($PSCompletions.config.menu_list_cover_buffer) {
        $box = @()
        foreach ($_ in 0..$PSCompletions.menu.ui_size.Height) {
            $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
        }
        $pos = @{
            X = 0
            Y = $PSCompletions.menu.pos.Y
        }
        if ($PSCompletions.menu.is_show_above) { $pos.Y -- }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }

    $border_box = @()
    $content_box = @()
    $line_top = [string]$PSCompletions.config.menu_line_top_left + $PSCompletions.config.menu_line_horizontal * ($PSCompletions.menu.list_max_width + $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right) + $PSCompletions.config.menu_line_top_right
    $border_box += $line_top
    foreach ($_ in 0..($PSCompletions.menu.ui_size.height - 3)) {
        $content_length = $PSCompletions.menu.get_length($PSCompletions.menu.filter_list[$_].ListItemText)
        $content = $PSCompletions.menu.filter_list[$_].ListItemText + ' ' * ($PSCompletions.menu.list_max_width - $content_length)
        $border_box += [string]$PSCompletions.config.menu_line_vertical + (' ' * ($PSCompletions.config.menu_list_margin_left + $PSCompletions.menu.list_max_width + $PSCompletions.config.menu_list_margin_right)) + [string]$PSCompletions.config.menu_line_vertical
        $content_box += (' ' * $PSCompletions.config.menu_list_margin_left) + $content + (' ' * $PSCompletions.config.menu_list_margin_right)
    }
    $status = "$(([string]($PSCompletions.menu.selected_index + 1)).PadLeft($PSCompletions.menu.filter_list.Count.ToString().Length, ' '))"
    $line_bottom = [string]$PSCompletions.config.menu_line_bottom_left + $PSCompletions.config.menu_line_horizontal * 2 + ' ' * ($status.Length + 1) + $PSCompletions.config.menu_line_horizontal * ($PSCompletions.menu.list_max_width + $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right - $status.Length - 3) + $PSCompletions.config.menu_line_bottom_right
    $border_box += $line_bottom

    $buffer = $Host.UI.RawUI.NewBufferCellArray($border_box, $PSCompletions.config.menu_color_border_text, $PSCompletions.config.menu_color_border_back)
    $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.pos, $buffer)

    $buffer = $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.menu_color_item_text, $PSCompletions.config.menu_color_item_back)
    $pos = @{
        X = $PSCompletions.menu.pos.X + 1
        Y = $PSCompletions.menu.pos.Y + 1
    }
    $Host.UI.RawUI.SetBufferContents($pos, $buffer)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_list_buffer {
    param([int]$offset)
    $content_box = @()
    foreach ($_ in $offset..($PSCompletions.menu.ui_size.height - 3 + $offset)) {
        $content_length = $PSCompletions.menu.get_length($PSCompletions.menu.filter_list[$_].ListItemText)
        $content = $PSCompletions.menu.filter_list[$_].ListItemText + ' ' * ($PSCompletions.menu.list_max_width - $content_length)
        $content_box += (' ' * $PSCompletions.config.menu_list_margin_left) + $content + (' ' * $PSCompletions.config.menu_list_margin_right)
    }
    $buffer = $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.menu_color_item_text, $PSCompletions.config.menu_color_item_back)
    $pos = @{
        X = $PSCompletions.menu.pos.X + 1
        Y = $PSCompletions.menu.pos.Y + 1
    }
    $Host.UI.RawUI.SetBufferContents($pos, $buffer)
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

    $char = $PSCompletions.config.menu_filter_symbol
    $mindle = [System.Math]::Ceiling($char.Length / 2)
    $start = $char.Substring(0, $mindle)
    $end = $char.Substring($mindle)

    $buffer_filter = $Host.UI.RawUI.NewBufferCellArray(@(@($start, $filter, $end) -join ''), $PSCompletions.config.menu_color_filter_text, $PSCompletions.config.menu_color_filter_back)
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
        $Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.menu_above_margin_bottom
    }
    else {
        $Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_size.height - 1
    }

    $old_top = New-Object System.Management.Automation.Host.Coordinates $X, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.UI.RawUI.BufferSize.Width, $Y

    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))

    $PSCompletions.menu.old_status_buffer = $old_buffer  # 之前的内容
    $PSCompletions.menu.old_status_pos = $old_top  # 之前的位置

    $current = "$(([string]($PSCompletions.menu.selected_index + 1)).PadLeft($PSCompletions.menu.filter_list.Count.ToString().Length, ' '))"
    $buffer_status = $Host.UI.RawUI.NewBufferCellArray(@("$current$($PSCompletions.config.menu_status_symbol)$($PSCompletions.menu.filter_list.Count)"), $PSCompletions.config.menu_color_status_text, $PSCompletions.config.menu_color_status_back)

    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $buffer_status)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_old_tip_buffer {
    param([int]$X, [int]$Y)
    if ($PSCompletions.config.menu_tip_cover_buffer) {
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
    if ($PSCompletions.config.menu_tip_cover_buffer) {
        if ($PSCompletions.menu.is_show_above) {
            foreach ($_ in 0..($PSCompletions.menu.pos.Y - 1)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = 0
            }
        }
        else {
            foreach ($_ in 0..($Host.UI.RawUI.BufferSize.Height - $PSCompletions.menu.pos_tip.Y)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = $PSCompletions.menu.pos_tip.Y - 1
            }
        }
    }
    else {
        foreach ($_ in 0..($PSCompletions.menu.tip_max_height + 1)) {
            $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
        }
        $pos = @{
            X = 0
            Y = $PSCompletions.menu.pos_tip.Y - 1
        }
        if ($PSCompletions.menu.is_show_above) {
            $pos.Y = [Math]::Max($pos.Y, 0)
        }
    }
    $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
    $Host.UI.RawUI.SetBufferContents($pos, $buffer)

    if ($PSCompletions.menu.filter_list[$index].ToolTip) {
        $pos = @{
            X = $PSCompletions.menu.pos_tip.X
            Y = $PSCompletions.menu.pos_tip.Y
        }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($PSCompletions.menu.filter_list[$index].ToolTip, $PSCompletions.config.menu_color_tip_text, $PSCompletions.config.menu_color_tip_back)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_selection {
    if ($PSCompletions.menu.old_selection) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_selection.pos, $PSCompletions.menu.old_selection.buffer)
    }

    $X = $PSCompletions.menu.pos.X + 1
    $to_X = $X + $PSCompletions.menu.list_max_width - 1
    # 如果高亮需要包含 margin
    if ($PSCompletions.config.menu_selection_with_margin) {
        $to_X += $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right
    }
    else {
        $X += $PSCompletions.config.menu_list_margin_left
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
    # 对于多字节字符，会过滤掉 Trailing 类型字符以确保正确渲染
    $content = foreach ($i in $LineBuffer.Where({ $_.BufferCellType -ne 'Trailing' })) { $i.Character }
    $LineBuffer = $Host.UI.RawUI.NewBufferCellArray(
        @([string]::Join('', $content)),
        $PSCompletions.config.menu_color_selected_text,
        $PSCompletions.config.menu_color_selected_back
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

    if ($PSCompletions.config.menu_is_loop) {
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
    elseif ($PSCompletions.config.menu_is_loop -or ($new_selected_index -ge 0 -and $new_selected_index -lt $PSCompletions.menu.filter_list.Count)) {
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
        if ($text) {
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
    if ($PSCompletions.config.menu_is_prefix_match) {
        $match = "$($PSCompletions.menu.filter)*"
    }
    else {
        $match = "*$($PSCompletions.menu.filter)*"
    }
    $PSCompletions.menu.filter_list = @()

    foreach ($f in $filter_list) {
        if ($f.CompletionText -and $f.CompletionText -like $match) {
            $PSCompletions.menu.filter_list += $f
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod reset {
    param([bool]$clearAll, [bool]$is_menu_enhance)
    # reset content

    if ($PSCompletions.menu.old_tip_buffer) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_tip_buffer.top, $PSCompletions.menu.old_tip_buffer.buffer)
    }

    if ($PSCompletions.menu.old_menu_buffer) {
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
    $PSCompletions.menu.tip_max_height = 0

    if ($is_menu_enhance) {
        $PSCompletions.menu.is_show_tip = $PSCompletions.config.menu_show_tip_when_enhance -eq 1
    }
    else {
        if ($PSCompletions.current_cmd) {
            $menu_show_tip = $PSCompletions.config.comp_config.$($PSCompletions.current_cmd).menu_show_tip
            if ($menu_show_tip -ne $null) {
                $PSCompletions.menu.is_show_tip = $menu_show_tip -eq 1
            }
            else {
                $PSCompletions.menu.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
            }
        }
        else {
            $PSCompletions.menu.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
    param($filter_list, [bool]$is_menu_enhance)

    if (!$filter_list) { return }

    $lastest_encoding = [console]::OutputEncoding
    [console]::OutputEncoding = $PSCompletions.encoding

    $PSCompletions.menu.pos = @{ X = 0; Y = 0 }
    $PSCompletions.menu.pos_tip = @{ X = 0; Y = 0 }
    $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.config.menu_list_min_width)

    $PSCompletions.menu.ui_size = $Host.UI.RawUI.BufferSize

    $PSCompletions.menu.filter = ''  # 过滤的关键词
    $PSCompletions.menu.old_filter = ''

    $PSCompletions.menu.page_current_index = 0 # 当前显示第几个

    $PSCompletions.menu.selected_index = 0  # 当前选中的索引
    $PSCompletions.menu.old_selected_index = 0

    $PSCompletions.menu.offset = 0  # 索引的偏移量，用于滚动翻页

    $PSCompletions.menu.reset($true, $is_menu_enhance)

    $PSCompletions.menu.origin_filter_list = @()
    $PSCompletions.menu.filter_list = @()
    $PSCompletions.menu.handle_list_first($filter_list)

    if ($PSCompletions.config.enter_when_single -and $PSCompletions.menu.filter_list.Count -eq 1) {
        return $PSCompletions.menu.filter_list[$PSCompletions.menu.selected_index].CompletionText
    }
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
            Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_size.height - 1
        })

    if ($PSCompletions.menu.is_show_tip) { $PSCompletions.menu.get_old_tip_buffer($PSCompletions.menu.pos_tip.X, $PSCompletions.menu.pos_tip.Y) }
    # 显示菜单
    $PSCompletions.menu.new_buffer()
    if ($PSCompletions.menu.is_show_tip) { $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index) }
    if ($PSCompletions.config.menu_is_prefix_match) { $PSCompletions.menu.get_prefix() }
    $PSCompletions.menu.new_filter_buffer($PSCompletions.menu.filter)
    $PSCompletions.menu.new_status_buffer()
    $PSCompletions.menu.set_selection()
    $old_filter_list = $PSCompletions.menu.filter_list
    :loop while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode) {
        $shift_pressed = 0x10 -band [int]$PressKey.ControlKeyState
        if ($PressKey.ControlKeyState -like '*CtrlPressed*') {
            switch ($PressKey.VirtualKeyCode) {
                67 {
                    # 67: Ctrl + c
                    $PSCompletions.menu.reset($true)
                    ''
                    break loop
                }
                { $_ -eq 85 -or $_ -eq 80 } {
                    # 85: Ctrl + u
                    # 80: Ctrl + p
                    $PSCompletions.menu.move_selection($false)
                    break
                }

                { $_ -eq 68 -or $_ -eq 78 } {
                    # 68: Ctrl + d
                    # 78: Ctrl + n
                    $PSCompletions.menu.move_selection($true)
                    break
                }
            }
        }
        switch ($PressKey.VirtualKeyCode) {
            { $_ -in @(9, 32) } {
                # 9: Tab
                # 32: Space
                if ($PSCompletions.menu.filter_list.Count -eq 1) {
                    $PSCompletions.menu.reset($true)
                    $PSCompletions.menu.filter_list[$PSCompletions.menu.selected_index].CompletionText
                    break loop
                }
                if ($shift_pressed) {
                    # Up
                    $PSCompletions.menu.move_selection($false)
                }
                else {
                    # Down
                    $PSCompletions.menu.move_selection($true)
                }
                break
            }
            27 {
                # 27: ESC
                $PSCompletions.menu.reset($true)
                ''
                break loop
            }
            13 {
                # 13: Enter
                $PSCompletions.menu.filter_list[$PSCompletions.menu.selected_index].CompletionText
                $PSCompletions.menu.reset($true)
                break loop
            }

            # 向上
            # 37: Up
            # 38: Left
            { $_ -in @(37, 38) } {
                $PSCompletions.menu.move_selection($false)
                break
            }
            # 向下
            # 39: Right
            # 40: Down
            { $_ -in @(39, 40) } {
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
                        $PSCompletions.menu.reset($true)
                        ''
                        break loop
                    }
                    if ($PSCompletions.menu.filter) {
                        $PSCompletions.menu.filter = $PSCompletions.menu.filter.Substring(0, $PSCompletions.menu.filter.Length - 1)
                    }
                    else {
                        $PSCompletions.menu.reset($true)
                        ''
                        break loop
                    }
                    $PSCompletions.menu.new_cover_buffer()
                    $PSCompletions.menu.reset()
                    $PSCompletions.menu.filter_completions($PSCompletions.menu.origin_filter_list)
                    foreach ($item in $PSCompletions.menu.filter_list) {
                        $PSCompletions.menu.tip_max_height = [Math]::Max($PSCompletions.menu.tip_max_height, $item.ToolTip.Count)
                    }
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
                        $PSCompletions.menu.reset()
                        foreach ($item in $PSCompletions.menu.filter_list) {
                            $PSCompletions.menu.tip_max_height = [Math]::Max($PSCompletions.menu.tip_max_height, $item.ToolTip.Count)
                        }

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
    [console]::OutputEncoding = $lastest_encoding
    $PSCompletions.menu.list_max_width = 0
}
