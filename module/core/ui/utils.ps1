$PSCompletions.ui | Add-Member -MemberType ScriptMethod get_list {
	param(
		[object[]]$content,
		[ref]$repeat
	)
	$is_single = if ($content[1]) { $false }else { $true }

	# create console list
	$prefix = $PSCompletions.ui.get_prefix($content)
	$filter = ''
	$color = $PSCompletions.ui.color
	$ListHandle = $PSCompletions.ui.new_list($content)

	function set_status {
		# filter buffer (header) shows the current filter after the last word
		$filter_buffer = $PSCompletions.ui.new_buffer_cell(" $prefix$($PSCompletions.ui.config.filter_symbol[0])$filter$($PSCompletions.ui.config.filter_symbol[1]) ", $color.filter_text, $color.filter_back)
		$filter_position = $ListHandle.Position
		$filter_position.X += 2
		$filter_handle = $PSCompletions.ui.new_buffer($filter_position, $filter_buffer)

		# status buffer (footer) shows selected item number, visible items number range, total item count
		$status_buffer = $PSCompletions.ui.new_buffer_status($ListHandle)
		$status_position = $ListHandle.Position
		$status_position.X += 2
		$status_position.Y += $listHandle.ListConfig.ListHeight - 1
		$status_handle = $PSCompletions.ui.new_buffer($status_position , $status_buffer)
	}
	. set_status

	function show_tip {
		$tip_buffer = $PSCompletions.ui.get_tip($ListHandle.items[$ListHandle.selected_item].CompletionText)
		$tip_position = $ListHandle.Position
		$tip_position.X += $PSCompletions.ui.layout.list_w
		$tip_position.Y += 1
		$tip_handle = $PSCompletions.ui.new_buffer($tip_position, $tip_buffer, $tip_position.X)
	}
	. show_tip
	# select the first item
	$selected_item = 0
	$PSCompletions.ui.set_selection(1 , ($selected_item + 1) , ($ListHandle.ListConfig.ListWidth - 3), $color.selected_text, $color.selected_back)

	### Keys
	:loop while (($Key = $PSCompletions.ui.ui.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode -ne 27) {
		$shift_pressed = 0x10 -band [int]$Key.ControlKeyState
		switch ($Key.VirtualKeyCode) {
			### Tab
			9 {
				if ($is_single -or $items.count -eq 1) {
					# out selected
					$ListHandle.items[$ListHandle.selected_item].CompletionText
					break loop
				}
				if ($shift_pressed) {
					# Up
					$PSCompletions.ui.move_selection(-1)
				}
				else {
					# Down
					$PSCompletions.ui.move_selection(1)
				}
				break
			}
			### Up Arrow
			38 {
				if ($shift_pressed) {
					# fast scroll selected
					if ($PSCompletions.ui.config.fast_scroll_item_count -gt ($ListHandle.items.count - 1)) {
						$count = $ListHandle.items.count - 1
					}
					else {
						$count = $PSCompletions.ui.config.fast_scroll_item_count
					}
					$PSCompletions.ui.move_selection(-$count)
				}
				else {
					$PSCompletions.ui.move_selection(-1)
				}
				break
			}
			### Down Arrow
			40 {
				if ($shift_pressed) {
					# fast scroll selected
					if ($PSCompletions.ui.config.fast_scroll_item_count -gt ($ListHandle.items.count - 1)) {
						$count = $ListHandle.items.count - 1
					}
					else {
						$count = $PSCompletions.ui.config.fast_scroll_item_count
					}
					$PSCompletions.ui.move_selection($count)
				}
				else {
					$PSCompletions.ui.move_selection(1)
				}
				break
			}
			### Page Up
			33 {
				$count = $ListHandle.items.count
				if ($count -gt $ListHandle.max_items) {
					$count = $ListHandle.max_items
				}
				$PSCompletions.ui.move_selection(1 - $count)
				break
			}
			### Page Down
			34 {
				$count = $ListHandle.items.count
				if ($count -gt $ListHandle.max_items) {
					$count = $ListHandle.max_items
				}
				$PSCompletions.ui.move_selection($count - 1)

				break
			}
			### Enter
			13 {
				# out selected
				$ListHandle.items[$ListHandle.selected_item].CompletionText
				break loop
			}
			### Character/Backspace
			{ $Key.Character } {
				# update filter
				$old_filter = $filter
				if ($Key.Character -eq 8) {
					if ($filter) {
						$filter = $filter.Substring(0, $filter.Length - 1)
					}
					else { break loop }
				}
				else {
					# add char
					$filter += $Key.Character
				}
				# get new items
				$items = @($PSCompletions.ui.select_item($content, $prefix, $filter))
				if (!$items) {
					# new filter gives no items, undo
					$filter = $old_filter
				}
				elseif ($items.count -ne $ListHandle.items.count) {
					# items changed, update
					$ListHandle.clear()
					$ListHandle = $PSCompletions.ui.new_list($items)
					# update status buffer
					. set_status
					. show_tip
					# select first item
					$selected_item = 0
					$PSCompletions.ui.set_selection(1 , ($selected_item + 1) , ($ListHandle.ListConfig.ListWidth - 3) , $color.selected_text, $color.selected_back)
				}
				else {
					# update status buffer
					. set_status
					. show_tip
				}
				break
			}
		}
	}
	$ListHandle.clear()
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod new_box {
	param(
		$size,
		[System.ConsoleColor]$color,
		[System.ConsoleColor]$bg_color
	)
	$margin = $PSCompletions.ui.config.tip_margin_right
	$line_top = $PSCompletions.ui.config.line.top_left + $PSCompletions.ui.config.line.horizontal * ($size.width - 5 + $margin) + $PSCompletions.ui.config.line.top_right
	$line_field = $PSCompletions.ui.config.line.vertical + ' ' * ($size.width - 5 + $margin) + $PSCompletions.ui.config.line.vertical
	$line_bottom = $PSCompletions.ui.config.line.bottom_left + $PSCompletions.ui.config.line.horizontal * ($size.width - 5 + $margin) + $PSCompletions.ui.config.line.bottom_right

	$Box = $(
		$line_top
		1..($size.Height - 2) | .{ process { $line_field } }
		$line_bottom
	)
	$BoxBuffer = $PSCompletions.ui.ui.NewBufferCellArray($Box, $color, $bg_color)
	, $BoxBuffer
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod get_size {
	param([object[]]$content)
	$max_width = ($content | ForEach-Object { $PSCompletions.ui.get_length($_.ListItemText) } | Measure-Object -Maximum).Maximum
	@{
		Width  = $max_width
		Height = $content.Length
	}
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod new_position {
	param(
		[int]$X, [int]$Y
	)
	$position = $PSCompletions.ui.ui.WindowPosition
	if ($PSCompletions.ui.config.follow_cursor) {
		$position.X += $X
	}
	else {
		$position.X += 0
	}
	$position.Y += $Y
	$position
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod new_buffer {
	param(
		[System.Management.Automation.Host.Coordinates]$Position,
		[System.Management.Automation.Host.BufferCell[, ]]$Buffer,
		[int]$offsetX = 0
	)
	$BufferBottom = $BufferTop = $Position
	$BufferBottom.X += ($Buffer.GetUpperBound(1))
	$BufferBottom.Y += ($Buffer.GetUpperBound(0))

	$OldTop = New-Object System.Management.Automation.Host.Coordinates $offsetX, $BufferTop.Y
	$OldBottom = New-Object System.Management.Automation.Host.Coordinates ($PSCompletions.ui.ui.BufferSize.Width - 1), $BufferBottom.Y
	$OldBuffer = $PSCompletions.ui.ui.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $OldTop, $OldBottom))
	$PSCompletions.ui.ui.SetBufferContents($BufferTop, $Buffer)
	$Handle = New-Object System.Management.Automation.PSObject -Property @{
		Content     = $Buffer
		OldContent  = $OldBuffer
		Location    = $BufferTop
		OldLocation = $OldTop
	}
	Add-Member -InputObject $Handle -MemberType ScriptMethod -Name clear -Value { $PSCompletions.ui.ui.SetBufferContents($this.OldLocation, $this.OldContent) }
	Add-Member -InputObject $Handle -MemberType ScriptMethod -Name Show -Value { $PSCompletions.ui.ui.SetBufferContents($this.Location, $this.Content) }
	$Handle
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod new_buffer_status {
	param($ListHandle)
	, $PSCompletions.ui.new_buffer_cell(" $($ListHandle.selected_item + 1) $($PSCompletions.ui.config.count_symbol) $($ListHandle.items.count) ", $PSCompletions.ui.color.status_text , $PSCompletions.ui.color.status_back)
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod new_buffer_cell {
	param(
		[string[]]$content,
		[System.ConsoleColor]$color,
		[System.ConsoleColor]$bg_color
	)
	, $PSCompletions.ui.ui.NewBufferCellArray($content, $color, $bg_color)
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod parse_list {
	param($size)
	$WindowPosition = $PSCompletions.ui.ui.WindowPosition
	$WindowSize = $PSCompletions.ui.ui.WindowSize
	$Cursor = $PSCompletions.ui.ui.CursorPosition
	$Center = [int]($WindowSize.Height / 2)
	$CursorOffset = $Cursor.Y - $WindowPosition.Y
	$CursorOffsetBottom = $WindowSize.Height - $CursorOffset

	# vertical size and placement
	$ListHeight = $size.Height + 2
	if (!$PSCompletions.ui.layout.Above) {
		$PSCompletions.ui.layout.Above = $WindowSize.Height - $Cursor.Y -lt $Cursor.Y - $PSCompletions.ui.style_h
	}
	if ($PSCompletions.ui.layout.Above) {
		$MaxListHeight = $CursorOffset - 1
		if ($MaxListHeight -lt $ListHeight) { $ListHeight = $MaxListHeight }
		$PSCompletions.ui.layout.Above_list_h = $Cursor.Y - ($PSCompletions.ui.style_h - 1)
		if ($ListHeight -lt $PSCompletions.ui.layout.Above_list_h) {
			$PSCompletions.ui.layout.Above_list_h = $ListHeight
		}
	}
	else {
		$MaxListHeight = $CursorOffsetBottom - 2
		if ($MaxListHeight -lt $ListHeight) { $ListHeight = $MaxListHeight }
		$Y = $CursorOffSet + 1
	}

	$max_items = $MaxListHeight - 2

	# horizontal
	$ListWidth = $size.Width + 2 + $PSCompletions.ui.config.list_margin_right
	if ($ListWidth -gt $WindowSize.Width) { $ListWidth = $Windowsize.Width }
	$Max = $ListWidth
	if (($Cursor.X + $Max) -lt ($WindowSize.Width - 2)) {
		$X = $Cursor.X
	}
	else {
		if (($Cursor.X - $Max) -gt 0) {
			$X = $Cursor.X - $Max
		}
		else {
			$X = $windowSize.Width - $Max
		}
	}
	if ($PSCompletions.ui.layout.Above -and $ListHeight -gt $PSCompletions.completion_max[1] + 2 -and $ListHeight -gt $Cursor.Y - $PSCompletions.ui.style_h) {
		switch ($PSCompletions.ui.config.above_list_max) {
			$null {
				$ListHeight = $PSCompletions.ui.config.above_list_max + 2
			 }
			 -1 {
				$ListHeight = $Cursor.Y - $PSCompletions.ui.style_h
			 }
			Default {
				if ($PSCompletions.ui.config.above_list_max -gt $Cursor.Y - $PSCompletions.ui.style_h) {
					$ListHeight = $Cursor.Y - $PSCompletions.ui.style_h
				}
				else {
					$ListHeight = $PSCompletions.ui.config.above_list_max + 2
				}
			}
		}
	}

	if ($ListHeight -lt $PSCompletions.completion_max[1] + 2) {
		$ListHeight = $PSCompletions.completion_max[1] + 2
	}
	if ($PSCompletions.ui.layout.Above) {
		$Y = $WindowSize.Height - $CursorOffsetBottom - $PSCompletions.ui.style_h - $ListHeight
	}
	# output
	@{
		TopX       = $X
		TopY       = $Y
		ListHeight = $ListHeight
		ListWidth  = $ListWidth
		max_items  = $max_items
	}
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod new_list {
	param([object[]]$content)
	$size = $PSCompletions.ui.get_size($content)
	$MinWidth = ([string]$content.count).Length * 4
	if ($size.Width -lt $MinWidth) { $size.Width = $MinWidth }
	$Lines = @(foreach ($Item in $content) { "$($Item.ListItemText) ".PadRight($size.Width + 2) })
	$ListConfig = $PSCompletions.ui.parse_list($size)

	$BoxSize = @{
		Width  = $ListConfig.ListWidth + $PSCompletions.completion_max[0] + 1
		Height = $ListConfig.ListHeight
	}
	$rest_w = [System.Console]::WindowWidth - $BoxSize.Width
	$BoxSize.Width += if ($rest_w -gt 10) { 5 }elseif ($rest_w -gt 0) { $rest_w }

	$PSCompletions.ui.layout.list_h = $BoxSize.Height

	$Box = $PSCompletions.ui.new_box($BoxSize, $PSCompletions.ui.color.border_text, $PSCompletions.ui.color.border_back)
	$Position = $PSCompletions.ui.new_position($ListConfig.TopX, $ListConfig.TopY)
	$box_handle = $PSCompletions.ui.new_buffer($Position, $Box)

	# place content
	$Position.X += 1
	$Position.Y += 1

	$contentBuffer = $PSCompletions.ui.new_buffer_cell(($Lines[0..($ListConfig.ListHeight - 3)]) , $PSCompletions.ui.color.item_text , $PSCompletions.ui.color.item_back)

	$contentHandle = $PSCompletions.ui.new_buffer($Position, $contentBuffer)

	$Handle = New-Object System.Management.Automation.PSObject -Property @{
		Position      = $PSCompletions.ui.new_position($ListConfig.TopX, $ListConfig.TopY)
		ListConfig    = $ListConfig
		ContentSize   = $size
		BoxSize       = $BoxSize
		Box           = $box_handle
		Content       = $contentHandle
		selected_item = 0
		selected_line = 1
		items         = $content
		Lines         = $Lines
		FirstItem     = 0
		LastItem      = $Listconfig.ListHeight - 3
		max_items     = $Listconfig.max_items
	}
	Add-Member -InputObject $Handle -MemberType ScriptMethod -Name clear -Value { $this.Box.clear() }
	Add-Member -InputObject $Handle -MemberType ScriptMethod -Name Show -Value { $this.Box.Show(); $this.Content.Show() }
	$Handle
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod get_length {
	param([string]$str)
	$matches = [System.Text.RegularExpressions.Regex]::Matches($str, '😄')
	$len = 0 + $matches.Count * 2
	$str = $str -replace '😄', ''
	foreach ($i in $str.ToCharArray()) {
		if ($i -match '[A-Za-z\d\s!@#\$%^&\*\(\)_\-\+\=\[\]{}|;:''",\.<>/?~`]') {
			$len++
		}
		else {
			$len += 2
		}
	}
	$len
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod get_tip {
	param($select_item)

	$tip = $PSCompletions.completion.$select_item

	while ($tip.count -lt $PSCompletions.completion_max[1]) {
		$tip += ''
	}
	, $PSCompletions.ui.new_buffer_cell($tip, $PSCompletions.ui.color.tip_text , $PSCompletions.ui.color.tip_back)
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod mv_list {
	param(
		[int]$X,
		[int]$Y,
		[int]$Width,
		[int]$Height,
		[int]$Offset
	)
	$Position = $ListHandle.Position
	$Position.X += $X
	$Position.Y += $Y
	$Rectangle = New-Object System.Management.Automation.Host.Rectangle $Position.X, $Position.Y, ($Position.X + $Width), ($Position.Y + $Height - 1)
	$Position.Y += $OffSet
	$BufferCell = New-Object System.Management.Automation.Host.BufferCell
	$BufferCell.BackgroundColor = $PSCompletions.ui.color.item_back
	$PSCompletions.ui.ui.ScrollBufferContents($Rectangle, $Position, $Rectangle, $BufferCell)
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod set_selection {
	param(
		[int]$X,
		[int]$Y,
		[int]$Width,
		[System.ConsoleColor]$ForegroundColor,
		[System.ConsoleColor]$BackgroundColor
	)
	$Position = $ListHandle.Position
	$Position.X += $X
	$Position.Y += $Y
	$Rectangle = New-Object System.Management.Automation.Host.Rectangle $Position.X, $Position.Y, ($Position.X + $Width), $Position.Y
	$LineBuffer = $PSCompletions.ui.ui.GetBufferContents($Rectangle)
	$LineBuffer = $PSCompletions.ui.ui.NewBufferCellArray(
		@([string]::Join('', ($LineBuffer | .{ process { $_.Character } }))),
		$ForegroundColor,
		$BackgroundColor
	)
	$PSCompletions.ui.ui.SetBufferContents($Position, $LineBuffer)
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod move_selection {
	param([int]$count)
	$color = $PSCompletions.ui.color
	$selected_item = $ListHandle.selected_item
	$Line = $ListHandle.selected_line
	if ($count -ge 0) {
		## Down in list
		if ($selected_item -eq ($ListHandle.items.count - 1)) {
			return
		}
		$One = 1
		if ($selected_item + $count -gt $ListHandle.items.count - 1) { $count = $ListHandle.items.count - 1 - $selected_item }
		if ($selected_item -eq $ListHandle.LastItem) {
			$Move = $true
		}
		else {
			$Move = $false
			if (($ListHandle.max_items - $Line) -lt $count) { $count = $ListHandle.max_items - $Line }
		}
	}
	else {
		if ($selected_item -eq 0) {
			return
		}
		$One = -1
		if ($selected_item -eq $ListHandle.FirstItem) {
			$Move = $true
			if ($selected_item + $count -lt 0) { $count = - $selected_item }
		}
		else {
			$Move = $false
			if ($Line + $count -lt 1) { $count = 1 - $Line }
		}
	}

	if ($Move) {
		$PSCompletions.ui.set_selection(1 , $Line, ($ListHandle.ListConfig.ListWidth - 3), $color.item_text, $color.item_back)
		$PSCompletions.ui.mv_list(1, 1, ($ListHandle.ListConfig.ListWidth - 3), ($ListHandle.ListConfig.ListHeight - 2), ( - $count))
		$selected_item += $count
		$ListHandle.FirstItem += $count
		$ListHandle.LastItem += $count

		$line_position = $ListHandle.Position
		$line_position.X += 1
		if ($One -eq 1) {
			$line_position.Y += $Line - ($count - $One)
			$ItemLines = $ListHandle.Lines[($selected_item - ($count - $One)) .. $selected_item]
		}
		else {
			$line_position.Y += 1
			$ItemLines = $ListHandle.Lines[($selected_item..($selected_item - ($count - $One)))]
		}
		$null = $PSCompletions.ui.new_buffer($line_position , $PSCompletions.ui.new_buffer_cell($ItemLines, $color.item_text, $color.item_back))
		$PSCompletions.ui.set_selection(1, $Line, ($ListHandle.ListConfig.ListWidth - 3) , $color.selected_text , $color.selected_back)
	}
	else {
		$PSCompletions.ui.set_selection(1, $Line, ($ListHandle.ListConfig.ListWidth - 3), $color.item_text , $color.item_back)
		$selected_item += $count
		$Line += $count
		$PSCompletions.ui.set_selection(1 , $Line, ($ListHandle.ListConfig.ListWidth - 3), $color.selected_text, $color.selected_back)
	}
	$ListHandle.selected_item = $selected_item
	$ListHandle.selected_line = $Line

	# new status buffer
	$status_handle.clear()
	$status_buffer = $PSCompletions.ui.new_buffer_status($ListHandle)
	$status_handle = $PSCompletions.ui.new_buffer($status_handle.Location, $status_buffer)
	# new tip buffer
	$tip_handle.clear()
	$tip_buffer = $PSCompletions.ui.get_tip($ListHandle.items[$ListHandle.selected_item].CompletionText)
	$tip_handle = $PSCompletions.ui.new_buffer($tip_handle.Location, $tip_buffer)
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod select_item {
	param($content, $prefix, $filter)
	$pattern = '^' + [regex]::Escape($prefix) + '.*?'
	foreach ($c in $filter.ToCharArray()) {
		$pattern += [regex]::Escape($c) + '.*?'
	}
	$prefix += $filter
	foreach ($_ in $content) {
		if ($_.ListItemText.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
			$_
		}
	}
	foreach ($_ in $content) {
		$s = $_.ListItemText
		if (!$s.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and $s -match $pattern) { $_ }
	}
}

$PSCompletions.ui | Add-Member -MemberType ScriptMethod get_prefix {
	param($content)
	$prefix = $content[-1].ListItemText
	for ($i = $content.count - 2; $i -ge 0 -and $prefix; --$i) {
		$text = $content[$i].ListItemText
		while ($prefix -and !$text.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
			$prefix = $prefix.Substring(0, $prefix.Length - 1)
		}
	}
	$prefix
}
