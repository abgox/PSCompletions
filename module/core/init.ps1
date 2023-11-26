New-Variable -Name _psc -Value @{}  -Option Constant
$_psc.version = '2.2.5'
$_psc.path = @{}
$_psc.path.root = Split-Path $PSScriptRoot -Parent
$_psc.path.completions = $_psc.path.root + '\completions'
$_psc.path.core = $_psc.path.root + '\core'
$_psc.path.list = $_psc.path.root + '\list.txt'
$_psc.path.old_list = $_psc.path.core + '\.old_list'
$_psc.path.update = $_psc.path.core + '\.update'
$_psc.lang = (Get-WinSystemLocale).name
$_psc.langs = @('zh-CN', 'en-US')
$_psc.comp_data = [ordered]@{}

#region : Add function
$_psc | Add-Member -MemberType ScriptMethod fn_replace {
    param ([array]$data)
    $data = $data -join ''
    $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
    $matches = [regex]::Matches($data, $pattern)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value))
    }
    if ($data -match $pattern) { $_psc.fn_replace($data) }else { return $data }
}
$_psc | Add-Member -MemberType ScriptMethod fn_get_order {
    param (
        [string]$PSScriptRoots,
        [array]$exclude = @(),
        [string]$file = 'order.json'
    )
    $path_order = $PSScriptRoots + '\' + $file

    if (!(Test-Path($path_order))) {
        $json = Get-Content -Raw -Path ($PSScriptRoots + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
        $i = 1
        $res = [ordered]@{}
        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $exclude
        } | ForEach-Object {
            $res.$_ = $i++
        }
        $res | ConvertTo-Json | Out-File $path_order -Force
    }
    return (Get-Content -Raw $path_order -Encoding utf8 | ConvertFrom-Json)
}
$_psc | Add-Member -MemberType ScriptMethod fn_get_config {
    $c = [environment]::GetEnvironmentvariable('abgox_PSCompletions', 'User') -split ';'
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
$_psc | Add-Member -MemberType ScriptMethod fn_set_config {
    param (
        [string]$k,
        [string]$v
    )
    $c = $_psc.fn_get_config()
    $c.$k = $v
    $res = @($c.module_version, $c.root_cmd, $c.github, $c.gitee, $c.language, $c.update, $c.LRU) -join ';'
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
}
$_psc | Add-Member -MemberType ScriptMethod fn_get_content {
    param ([string]$path)
    return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' })
}
$_psc | Add-Member -MemberType ScriptMethod fn_confirm {
    param (
        [string]$tip,
        [scriptblock]$confirm_event,
        [string]$tip_color = 'Yellow',
        [string]$cancel_color = 'Green'
    )
    Write-Host $_psc.fn_replace($tip) -f $tip_color
    $choice = $host.UI.RawUI.ReadKey('NoEcho, IncludeKeyDown')
    if ($choice.Character -eq 13) { & $confirm_event }
    else { Write-Host $_psc.fn_replace($_psc.json.cancel) -f $cancel_color }
}
$_psc | Add-Member -MemberType ScriptMethod fn_download_list {
    try {
        if ($_psc.url) {
            $res = Invoke-WebRequest -Uri ($_psc.url + '/list.txt')
            if ($res.StatusCode -eq 200) {
                $content = $res.Content.Trim()
                $old_list = Get-Content $_psc.path.old_list -Raw -Encoding utf8
                $list = Get-Content $_psc.path.list -Raw -Encoding utf8
                if ($old_list -ne $list) {
                    Copy-Item $_psc.path.list $_psc.path.old_list -Force
                }
                if (!$list) { $list = '' }
                if ($content -ne $list.Trim()) {
                    $content | Out-File $_psc.path.list -Force -Encoding utf8
                    $_psc.list = $_psc.fn_get_content($_psc.path.list)
                }
                return $content
            }
        }
        else {
            Write-Host $_psc.fn_replace($_psc.json.repo_add) -f Red
            return $false
        }
    }
    catch { return $false }
}
$_psc | Add-Member -MemberType ScriptMethod fn_add_completion {
    param (
        [string]$completion,
        [bool]$log = $true,
        [bool]$is_update = $false
    )
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
        if (!(Test-Path($path))) { New-Item -ItemType Directory $path > $null }
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
            Uri     = $url + '/.guid'
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

    Write-Host $_psc.fn_replace($flag) -f Yellow
    Write-Host $_psc.fn_replace($_psc.json.repo_using) -f Cyan
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
            Write-Host  $_psc.fn_replace($done) -f Green
            Write-Host $_psc.fn_replace($_psc.json.download_dir + $completion_dir) -f Green
        }
    }
    else {
        Write-Host  $_psc.fn_replace($err) -f Red
        Remove-Item $completion_dir -Force -Recurse > $null
    }
}
$_psc | Add-Member -MemberType ScriptMethod fn_less {
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
        Write-Host $_psc.fn_replace($_psc.json.less_tip) -f Cyan
        Write-Host '--------------------' -f Yellow
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
        $str_list | ForEach-Object { Write-Host $_ -f $color }
    }
}
$_psc | Add-Member -MemberType ScriptMethod fn_less_table {
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
        Write-Host $_psc.fn_replace($_psc.json.less_tip) -f Cyan
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
#endregion

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler 'Tab' MenuComplete
}
if (!(Test-Path($_psc.path.completions))) {
    mkdir $_psc.path.completions > $null
}
if (!(Test-Path($_psc.path.list)) -or ([environment]::GetEnvironmentvariable('abgox_PSCompletions', 'User') -split ';')[0] -ne $_psc.version) {
    #region move old completions
    $version = (Get-ChildItem (Split-Path $_psc.path.root -Parent)).Name | Sort-Object { [Version] $_ } -ErrorAction SilentlyContinue
    if ($version -is [array]) { $version = $version[-2] }
    $old = (Get-ChildItem ((Split-Path $_psc.path.root -Parent) + '\' + $version + '\' + 'completions') -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -ne 'PSCompletions' }).FullName
    if ($old) { Move-Item $old $_psc.path.completions -Force -ErrorAction SilentlyContinue }
    #endregion

    #region init env
    $config = $_psc.fn_get_config()
    if ($config.module_version) {
        $root_cmd = $config.root_cmd
        $github = $config.github
        $gitee = $config.gitee
        $language = $config.language
        $update = if ($config.update -eq 0) { 0 } else { 1 }
        $LRU = $config.LRU
    }
    else {
        $root_cmd = 'psc'
        $github = 'https://github.com/abgox/PSCompletions'
        $gitee = 'https://gitee.com/abgox/PSCompletions'
        $language = $_psc.lang
        $update = 1
        $LRU = 5
    }
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', (@($_psc.version, $root_cmd, $github, $gitee, $language, $update, $LRU) -join ';'), 'User')
    #endregion

    $_psc.init = $true
}

$_psc | Add-Member -MemberType ScriptMethod fn_init {
    $_psc.comp_cmd = [ordered]@{}
    $_psc.config = $_psc.fn_get_config()
    $_psc.root_cmd = $_psc.config.root_cmd

    if ($_psc.config.language) {
        $_psc.lang = $_psc.config.language
    }
    if ($_psc.config.github) {
        $_psc.github = $_psc.config.github.Replace('github.com', 'raw.githubusercontent.com') + '/main'
    }
    if ($_psc.config.gitee) {
        $_psc.gitee = $_psc.config.gitee + '/raw/main'
    }
    function _do($i, $k) {
        if ($_psc.config.$i) { return @($_psc.$i, $_psc.config.$i) }
        else { return @($_psc.$k, $_psc.config.$k) }
    }
    if ($_psc.lang -eq 'zh-CN') {
        $info = _do 'gitee' 'github'
        $_psc.url = $info[0]
        $_psc.repo = $info[1]
    }
    else {
        $info = _do 'github' 'gitee'
        $_psc.url = $info[0]
        $_psc.repo = $info[1]
        $_psc.lang = 'en-US'
    }

    $psc_alias_path = $_psc.path.completions + '\PSCompletions\.alias'
    $psc_json_path = $_psc.path.completions + '\PSCompletions\json\' + $_psc.lang + '.json'

    try {
        if (!(Test-Path($psc_json_path))) {
            $psc_temp = $env:TEMP + '\PSCompletion.json'
            Invoke-WebRequest -Uri ($_psc.url + '/completions/PSCompletions/json/' + $_psc.lang + '.json') -OutFile $psc_temp
            $_psc.json = (Get-Content -Path $psc_temp -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue).PSCompletions_core_info
            $_psc.fn_add_completion('PSCompletions')
            Remove-Item -Force $psc_temp -ErrorAction SilentlyContinue
        }
        if (!(Test-Path($psc_alias_path))) {
            $_psc.root_cmd | Out-File $psc_alias_path -Force -Encoding utf8
        }
        $psc_alias = (Get-Content $psc_alias_path -Raw -Encoding utf8).Trim()
        if ($psc_alias -ne $_psc.root_cmd) {
            $_psc.fn_set_config('root_cmd', $psc_alias)
            $_psc.root_cmd = $_psc.config.root_cmd = $psc_alias
        }
        $_psc.json = (Get-Content -Path $psc_json_path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue).PSCompletions_core_info
        if (!(Test-Path($_psc.path.update))) {
            New-Item $_psc.path.update > $null
        }
        if (!(Test-Path($_psc.path.list))) {
            New-Item $_psc.path.list > $null
            if (!($_psc.fn_download_list())) { throw }
        }
        if (!(Test-Path($_psc.path.old_list))) {
            Copy-Item $_psc.path.list $_psc.path.old_list -Force
        }
        $_psc.list = $_psc.fn_get_content($_psc.path.list)
        $_psc.update = $_psc.fn_get_content($_psc.path.update)
    }
    catch { throw $_psc.fn_replace($_psc.json.init_err) }

    $res = [System.Collections.Generic.List[string]]@()
    $_psc.installed = Get-ChildItem -Path $_psc.path.completions -Filter '*.ps1' -Recurse -Depth 1 | Sort-Object CreationTime
    $_psc.installed | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        $_psc.comp_cmd.$cmd = $cmd
        $res.Add($_.FullName)
    }
    Get-ChildItem -Path $_psc.path.completions -Filter '.alias' -Recurse -Depth 1 | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent)  -Leaf
        $_psc.comp_cmd.$cmd = (Get-Content $_.FullName -Raw).Trim()
    }
    $res | ForEach-Object { . $_ }
}

$_psc.fn_init()

$_psc.comp_cmd.keys | Where-Object { $_psc.comp_cmd.$_ -ne $_ } | ForEach-Object { Set-Alias $_psc.comp_cmd.$_ $_ }

if (!$_psc.config.github -and !$_psc.config.gitee) {
    Write-Host $_psc.fn_replace($_psc.json.repo_err) -f Yellow
}

#region init and update
if ($_psc.init) { $_psc.fn_less($_psc.fn_replace($_psc.json.init_info), 'Cyan') }

if ($_psc.config.update -ne 0) {
    if ($_psc.config.update -ne 1) {
        $_psc.fn_confirm($_psc.json.module_update, {
                try {
                    Write-Host $_psc.fn_replace($_psc.json.module_updating) -f Cyan
                    Update-Module PSCompletions
                    $version_list = (Get-ChildItem (Split-Path $_psc.path.root -Parent)).BaseName
                    if ($_psc.config.update -in $version_list) {
                        Write-Host $_psc.fn_replace($_psc.json.module_update_done) -f Green
                    }
                    else {
                        Write-Host $_psc.fn_replace($_psc.json.module_update_err) -f Red
                    }
                }
                catch {
                    Write-Host $_psc.fn_replace($_psc.json.module_update_err) -f Red
                }
            })
    }
    else {
        $add = $_psc.fn_get_content($_psc.path.core + '\.add')
        if ($_psc.update -or $add) {
            Write-Host $_psc.fn_replace($_psc.json.update_info ) -f Cyan
            if ($add) {
                Write-Host $_psc.fn_replace($_psc.json.update_info_add) -f Cyan
                Clear-Content ($_psc.path.core + '\.add')
            }
            if ($_psc.update) {
                Write-Host $_psc.fn_replace($_psc.json.update_info_modify) -f Cyan
                Clear-Content $_psc.path.update
            }
            Write-Host $_psc.fn_replace($_psc.json.update_tip) -f Cyan
        }
    }
}
#endregion

$_psc.jobs = Start-Job -ScriptBlock {
    param( $_psc, $path_history )
    function get_content([string]$path) {
        return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' })
    }
    function get_order {
        param (
            [string]$PSScriptRoots,
            [array]$exclude = @(),
            [string]$file = 'order.json'
        )
        $path_order = $PSScriptRoots + '\' + $file

        if (!(Test-Path($path_order))) {
            $json = Get-Content -Raw -Path ($PSScriptRoots + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
            $i = 1
            $res = [ordered]@{}
            $json.PSObject.Properties.Name | Where-Object {
                $_ -notin $exclude
            } | ForEach-Object {
                $res.$_ = $i++
            }
            $res | ConvertTo-Json | Out-File $path_order -Force
        }
        return (Get-Content -Raw $path_order -Encoding utf8 | ConvertFrom-Json)
    }

    $alias_list = $_psc.comp_cmd.Keys | ForEach-Object { $_psc.comp_cmd.$_ }
    $history = [System.Collections.Generic.List[string]]@()

    [array](get_content $path_history) | ForEach-Object {
        $cmd = ($_ -split '\s+')[0]
        if ($cmd -in $alias_list) {
            if ($cmd -in $history) {
                $null = $history.Remove($cmd)
            }
            $null = $history.Add($cmd)
        }
    }
    $cache = @()
    $history | ForEach-Object {
        if ($_ -notin $cache) { $cache += $_ }
    }
    $cmd_list = @{}
    $_psc.comp_cmd.Keys | ForEach-Object {
        $alias = $_psc.comp_cmd.$_
        $cmd_list.$alias = $_
    }

    $cache[ - ([int]$_psc.config.LRU)..-1] | ForEach-Object {
        $cmd_list.$_
    } | ForEach-Object {
        $alias = $_psc.comp_cmd.$_
        $_psc.comp_data.$alias = @{}
        $json = Get-Content -Raw -Path  "$($_psc.path.completions)\$($_)\json\$($_psc.lang).json" -Encoding UTF8 | ConvertFrom-Json

        $info = $_ + '_core_info'
        $_psc.comp_data.$($alias + '_info') = @{
            core_info = $json.$info
            exclude   = @($info)
            num       = -1
        }

        $order = get_order ($_psc.path.completions + '\' + $_) $_psc.comp_data.$($alias + '_info').exclude

        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $_psc.comp_data.$($alias + '_info').exclude
        } | ForEach-Object {
            $cmd = $_ -split ' '
            $_o = if ($order.$_) { $order.$_ }else { $_i++ }
            $_psc.comp_data.$alias[$alias + ' ' + $_] = @($cmd[-1], $json.$_, $_o)
        }
    }
    return $_psc.comp_data
} -ArgumentList $_psc, (Get-PSReadLineOption).HistorySavePath

$null = Start-Job -ScriptBlock {
    param( $_psc )
    function _do($do) { try { & $do }catch {} }
    function _replace([array]$data) {
        $data = $data -join ''
        $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
        $matches = [regex]::Matches($data, $pattern)
        foreach ($match in $matches) {
            $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value))
        }
        if ($data -match $pattern) { _replace $data }else { return $data }

    }
    function download_list() {
        try {
            if ($_psc.url) {
                $res = Invoke-WebRequest -Uri ($_psc.url + '/list.txt')
                if ($res.StatusCode -eq 200) {
                    $content = $res.Content.Trim()
                    $old_list = Get-Content $_psc.path.old_list -Raw -Encoding utf8
                    $list = Get-Content $_psc.path.list -Raw -Encoding utf8
                    if ($old_list -ne $list) {
                        Copy-Item $_psc.path.list $_psc.path.old_list -Force
                    }
                    if ($content -ne $list.Trim()) {
                        $content | Out-File $_psc.path.list -Force -Encoding utf8
                    }
                    return $content
                }
            }
            else {
                return $false
            }
        }
        catch { return $false }
    }
    function get_config() {
        $c = [environment]::GetEnvironmentvariable('abgox_PSCompletions', 'User') -split ';'
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
    function set_config([string]$k, [string]$v) {
        $c = get_config
        $c.$k = $v
        $res = @($c.module_version, $c.root_cmd, $c.github, $c.gitee, $c.language, $c.update, $c.LRU) -join ';'
        [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
    }
    _do {
        $response = Invoke-WebRequest -Uri ($_psc.url + '/module/.version')
        if ($response.StatusCode -eq 200) {
            $content = $response.Content.Trim()
            $versions = @($_psc.version, $content) | Sort-Object { [Version] $_ }
            if ($versions[-1] -ne $_psc.version) {
                $res = Invoke-WebRequest -Uri ($_psc.url + '/module/log.json')
                if ($res.StatusCode -eq 200) {
                    $res.Content | Out-File ($_psc.path.core + '\log.json') -Force -Encoding utf8
                    set_config 'update' $versions[-1]
                }
            }
        }
    }

    $old_list = Get-Content $_psc.path.old_list -Encoding utf8
    $new_list = Get-Content $_psc.path.list -Encoding utf8
    $diff = Compare-Object $new_list $old_list -PassThru
    if ($diff) {
        $diff | Out-File ($_psc.path.core + '\.add') -Force -Encoding utf8
    }

    download_list

    $update_list = [System.Collections.Generic.List[string]]@()
    $installed = (Get-ChildItem -Path $_psc.path.completions -Filter '*.ps1' -Recurse -Depth 1).BaseName | Where-Object { $_ -in $_psc.list }

    $installed | ForEach-Object {
        $url = $_psc.url + '/completions/' + $_ + '/.guid'
        $response = Invoke-WebRequest -Uri  $url
        if ($response.StatusCode -eq 200) {
            $content = $response.Content.Trim()
            $guid = (Get-Content ($_psc.path.completions + '\' + $_ + '\.guid') -Raw).Trim()
            if ($guid -ne $content) { $update_list.Add($_) }
        }
    }
    $old_update_list = Get-Content $_psc.path.update -Encoding utf8

    if ($old_update_list) {
        if ($update_list) {
            $is_write = Compare-Object $update_list $old_update_list -PassThru
        }
        else {
            $is_write = $true
        }
    }
    elseif ($update_list) {
        $is_write = $true
    }

    if ($is_write) {
        $update_list | Out-File $_psc.path.update -Force -Encoding utf8
    }
} -ArgumentList $_psc
