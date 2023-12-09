$PSCompletions.ui.ui = $Host.UI.RawUI
$PSCompletions.ui.style_h = 2
. $PSScriptRoot\config.ps1
. $PSScriptRoot\utils.ps1

$PSCompletions.ui | Add-Member -MemberType ScriptMethod show {
	$filter_list = [array]$filter_list

	$PSCompletions.ui.layout = @{}

	$res = foreach ($i in $filter_list) {
		$cmd = $completions.$i[0]
		if ($cmd.length -gt $PSCompletions.ui.layout.cmd_max_w) {
			$PSCompletions.ui.layout.cmd_max_w = $cmd.length
		}
		@{
			CompletionText = $cmd
			ListItemText   = $cmd
		}
	}
	$PSCompletions.ui.layout.list_w = $PSCompletions.ui.layout.cmd_max_w + 4 + $PSCompletions.ui.config.list_margin_right

	if ($PSCompletions.ui.config.fllow_cursor) {
		$PSCompletions.ui.layout.tip_max_w = $PSCompletions.ui.ui.WindowSize.Width - $PSCompletions.ui.ui.CursorPosition.X - $PSCompletions.ui.layout.list_w - 5 + $PSCompletions.ui.config.tip_margin_right
	}
	else {
		$PSCompletions.ui.layout.tip_max_w = $PSCompletions.ui.ui.WindowSize.Width - $PSCompletions.ui.layout.list_w - 5 + $PSCompletions.ui.config.tip_margin_right
	}
	$max = @(0, 0, $filter_list.Count)
	$PSCompletions.completion = @{}
	foreach ($i in $filter_list) {
		$tool_tip = $PSCompletions.fn_replace($completions.$i[1]) -split "`n"
		if ($tool_tip.Count -eq 1) {
			$tool_tip += ' '
		}
		foreach ($item in $tool_tip) {
			$len = $PSCompletions.ui.get_length($item)
			if ($len -gt $max[0]) {
				$max[0] = $len
			}
		}
		function _do($str, $len) {
			while ($str.Length -gt $len) {
				$str.Substring(0, $len)
				$str = $str.Substring($len)
			}
			$str
		}
		if ($PSCompletions.lang -eq 'zh-CN') {
			$tool_tip = for ($j = 0; $j -lt $tool_tip.Count; $j++) {
				$len = $PSCompletions.ui.get_length($tool_tip[$j])
				if ($len -lt $PSCompletions.ui.layout.tip_max_w) {
					$tool_tip[$j]
					continue
				}
				$tip = $tool_tip[$j]
				$tip_max_w = $PSCompletions.ui.layout.tip_max_w - 1
				function _get_pos($str) {
					$len = $str.Length - 1
					while ($PSCompletions.ui.get_length($str) -ge $tip_max_w) {
						$str = $str.Substring(0, $len)
						$len--
					}
					return $len + 1
				}
				while ($PSCompletions.ui.get_length($tip) -gt $tip_max_w) {
					$split_pos = _get_pos $tip
					$tip.Substring(0, $split_pos)
					$tip = $tip.Substring($split_pos)
					if ($PSCompletions.ui.get_length($tip) -lt $tip_max_w) {
						$tip
					}
				}
			}
		}
		else {
			$tool_tip = foreach ($j in $tool_tip) {
				_do $j ($PSCompletions.ui.layout.tip_max_w - 5 + $PSCompletions.ui.config.tip_margin_right + 1)
			}
		}

		if ($tool_tip.Count -gt $max[1]) { $max[1] = $tool_tip.Count }
		$PSCompletions.completion.$($completions.$i[0]) = $tool_tip
	}

	$PSCompletions.completion_max = $max

	if ($PSCompletions.completion_max[0] -gt $PSCompletions.ui.layout.tip_max_w) {
		$PSCompletions.completion_max[0] = $PSCompletions.ui.layout.tip_max_w
	}

	$available_h = [System.Console]::WindowHeight - [System.Console]::CursorTop

	if ([System.Console]::CursorTop -eq 1) {
		$PSCompletions.ui.style_h = [System.Console]::CursorTop
	}

	if ($available_h -le 5) {
		''
		[Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
		[Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.json.min_area)
		return
	}

	if ($available_h - $max[1] -gt 3 -and $PSCompletions.ui.config.enable_ui) {
		''
		for () {
			$repeat = $false
			$replace = $PSCompletions.ui.get_list($res, ([ref]$repeat))
			$PSCompletions.ui.layout.Above = $null
			# apply the completion
			if ($replace) {
				$replace = $replace -replace ('^' + [regex]::Escape($word_to_complete)), ''
				[Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor_position, 0, $replace)
			}
			if (!$repeat) { break }
		}
		return
	}
	complete_by_old
}
