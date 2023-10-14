. $PSScriptRoot\replace.ps1

function _psc_get_config {
    $c = [environment]::GetEnvironmentvariable("abgox_PSCompletions", "User") -split ';'
    return @{
        module_version = $c[0]
        root_cmd       = $c[1]
        github         = $c[2]
        gitee          = $c[3]
        language       = $c[4]
        update         = $c[5]
        LRU            = $c[6]
    }
}

function _psc_set_config($k, $v) {
    $c = _psc_get_config
    $c.$k = $v
    $res = @($c.module_version, $c.root_cmd, $c.github, $c.gitee, $c.language, $c.update, $c.LRU) -join ';'
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
}

function _psc_confirm($tip, $confirm_event) {
    Write-Host (_psc_replace $tip) -f Yellow
    $choice = $host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
    if ($choice.Character -eq 13) {
        & $confirm_event
    }
    else { Write-Host (_psc_replace $_psc.json.cancel) -f Green }
}

function _psc_get_content($path) {
    return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' })
}

function _psc_download_list {
    try {
        if ($_psc.url) {
            $res = Invoke-WebRequest -Uri ($_psc.url + '/list.txt')
            if ($res.StatusCode -eq 200) {
                $content = ($res.Content).Trim()
                Move-Item  $_psc.path.list $_psc.path.old_list -Force
                $content | Out-File $_psc.path.list -Force -Encoding utf8
                $_psc.list = _psc_get_content $_psc.path.list
                return $true
            }
        }
        else {
            Write-Host (_psc_replace $_psc.json.repo_add) -f Red
            return $false
        }
    }
    catch { return $false }
}

function _psc_add_completion($completion, $log = $true, $is_update = $false) {
    if ($is_update) {
        $err = $_psc.json.update_download_err
        $done = $_psc.json.update_done
    }
    else {
        $err = $_psc.json.add_download_err
        $done = $_psc.json.add_done
    }
    $url = $_psc.url + '/completions/' + $completion
    function _mkdir($path) {
        if (!(Test-Path($path))) { mkdir $path > $null }
    }
    $completion_dir = $_psc.path.completions + '\' + $completion
    _mkdir $_psc.path.completions
    _mkdir $completion_dir
    _mkdir ($completion_dir + '\json')

    $files = @(
        @{
            Uri     = $url + '/' + $completion + '.ps1'
            OutFile = $completion_dir + '\' + $completion + '.ps1'
        },
        @{
            Uri     = $url + '/json/zh-CN.json'
            OutFile = $completion_dir + '\json\zh-CN.json'
        },
        @{
            Uri     = $url + '/json/en-US.json'
            OutFile = $completion_dir + '\json\en-US.json'
        },
        @{
            Uri     = $url + "/.guid"
            OutFile = $completion_dir + '\.guid'
        }
    )
    $jobs = @()
    foreach ($file in $files) {
        $params = $file
        $jobs += Start-Job -Name $file.OutFile -ScriptBlock {
            $params = $using:file
            Invoke-WebRequest @params
        }
    }
    $flag = if ($is_update) { $_psc.json.updating }else { $_psc.json.adding }

    Write-Host (_psc_replace $flag) -f Yellow
    Write-Host (_psc_replace $_psc.json.repo_using) -f Cyan
    Wait-Job -Job $jobs > $null

    $all_exist = $true
    foreach ($file in $files) {
        if (!(Test-Path $file.OutFile)) {
            $all_exist = $false
            $fail_file = Split-Path $file.OutFile -Leaf
            $fail_file_url = $file.Uri
        }
    }
    if ($all_exist) {
        if ($log) {
            Write-Host  (_psc_replace $done) -f Green
            Write-Host (_psc_replace ($_psc.json.download_dir + $completion_dir)) -f Green
        }
    }
    else {
        Write-Host  (_psc_replace $err) -f Red
        Remove-Item $completion_dir -Force -Recurse > $null
    }
}

function _psc_reorder_tab($history, $PSScriptRoots) {
    $null = Start-Job -ScriptBlock {
        param( $_psc, $history, $PSScriptRoots)
        if (!$history) { return }
        $comp_alias = $_psc.comp_cmd.keys | % { $_psc.comp_cmd.$_ }
        $his_arr = $history -split '\s+'
        if ($his_arr[0] -notin $comp_alias) { return }

        $json_path = $PSScriptRoots + '\json\' + $_psc.lang + '.json'
        $json_content = Get-Content $json_path -Raw -Encoding UTF8 | ConvertFrom-Json
        $all_cmd = $json_content.PSObject.Properties | ForEach-Object { $_.Name }

        $res = [System.Collections.Generic.List[string]]@()

        $all_cmd | ForEach-Object {
            $his = [System.Collections.Generic.List[string]]$his_arr[1..($his_arr.Count - 1)]
            $cmd = [System.Collections.Generic.List[string]]$($_ -split '\s+')
            $position = [System.Collections.Generic.List[int]]@()
            for ($i = 0; $i -lt $cmd.Count; $i++) {
                if ($cmd[$i] -match "<.+>") { $position.Add($i) }
            }
            if ($position) {
                foreach ($i in $position) {
                    if ($his.Count -gt $i) {
                        $cmd.RemoveAt($i)
                        $his.RemoveAt($i)
                    }
                }
            }
            while ($his) {
                $diff = Compare-Object $cmd $his -PassThru
                if (!$diff) { $res.Add($_) }
                if ($his.Count -eq 1) { break }
                $his = $his[0..($his.Count - 2)]
            }
        }
        $result_cmd = [System.Collections.Generic.List[string]]$all_cmd
        $res | Sort-Object { $_.Length } -Descending | ForEach-Object {
            $result_cmd.Remove($_) > $null
            $result_cmd.Insert(0, $_)
        }
        for ($i = 0; $i -lt $all_cmd.Count; $i++) {
            if ($result_cmd[$i] -ne $all_cmd[$i]) {
                $diff = $true
                break
            }
        }
        if ($diff) {
            $result_cmd | Out-File "$PSScriptRoots\.order"
        }

    } -ArgumentList $_psc, $history, $PSScriptRoots
}

function _psc_less($str_list, $header, $do = {}, $show_line) {
    if ($header) {
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
    }
    $i = 0
    $need_less = [System.Console]::WindowHeight -lt ($str_list.Count + 2)
    if ($need_less) {
        $init_line = if ($show_line) { $show_line }else { [System.Console]::WindowHeight - 5 }
        $lines = $str_list.Count - $init_line
        Write-Host (_psc_replace $_psc.json.less_tip) -f Cyan
        & $do
        while ($i -lt $init_line -and $i -lt $str_list.Count) {
            if ($str_list[$i].bgColor) {
                Write-Host $str_list[$i].content -f $str_list[$i].color -b $str_list[$i].bgColor
            }
            else {
                Write-Host $str_list[$i].content -f $str_list[$i].color
            }
            $i++
        }
        while ($i -lt $str_list.Count) {
            $keyCode = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
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
            Write-Host "(End)" -f Black -b White -NoNewline
            while ($end) {
                $keyCode = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
                if ($keyCode -ne 13) { break }
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

function _psc_parse_json_with_LRU($PSScriptRoots) {
    if ($_psc.comp_data.$root_cmd) {
        $json = $_psc.comp_data.$root_cmd
    }
    else {
        if ($_psc.comp_data.Count -eq $_psc.config.LRU) {
            $_psc.comp_data.RemoveAt(0)
        }
        $json = Get-Content -Raw -Path  ($PSScriptRoots + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
        $_psc.comp_data.$root_cmd = $json
    }
    return $json
}

function _psc_generate_order($PSScriptRoots) {
    $order = $PSScriptRoots + '\.order'
    try {
        $res = Get-Content $order -ErrorAction Stop
    }
    catch {
        $_path_json = $PSScriptRoots + '\json\' + $_psc.lang + '.json'
        $json = Get-Content -Raw -Path $_path_json -Encoding UTF8 | ConvertFrom-Json
        $_json = $json.PSObject.Properties
        $_json | ForEach-Object { $_.Name } | Where-Object { $_ -ne '' } | Out-File $order
        $res = Get-Content $order -ErrorAction Continue
    }
    return $res
}
