$PSCompletions | Add-Member -MemberType ScriptMethod fn_less {
    param (
        $str_list,
        [string]$color = 'Green',
        [int]$show_line = [System.Console]::WindowHeight - 5
    )
    if ($str_list -is [string]) {
        $str_list = $str_list -split "`n"
    }
    $i = 0
    $need_less = [System.Console]::WindowHeight -lt ($str_list.Count + 2)
    if ($need_less) {
        $lines = $str_list.Count - $show_line
        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.less_tip))
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
        $str_list | ForEach-Object {  Write-Host $_ -f $color }
    }
}
$PSCompletions | Add-Member -MemberType ScriptMethod fn_less_table {
    param (
        [array]$str_list,
        [array]$header = @('key', 'value', 5),
        [scriptblock]$do = {},
        [int]$show_line = [System.Console]::WindowHeight - 5
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
        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.less_tip))
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
        $str_list | ForEach-Object {
            if ($_.bgColor) {
                Write-Host $_.content -f $_.color -b $_.bgColor[2]
            }
            else {
                Write-Host $_.content -f $_.color
            }
        }
    }
}
