using namespace System.Management.Automation
using namespace System.Management.Automation.Language

New-Variable -Name PSCompletions -Value @{}  -Option Constant
$PSCompletions.version = '3.0.1'
$PSCompletions.path = @{}
$PSCompletions.path.root = Split-Path $PSScriptRoot -Parent
$PSCompletions.path.completions = $PSCompletions.path.root + '\completions'
$PSCompletions.path.core = $PSCompletions.path.root + '\core'
$PSCompletions.path.list = $PSCompletions.path.root + '\list.txt'
$PSCompletions.path.old_list = $PSCompletions.path.core + '\.old_list'
$PSCompletions.path.update = $PSCompletions.path.core + '\.update'
if ($PSVersionTable.Platform -ne 'Unix') {
    $PSCompletions.lang = (Get-WinSystemLocale).name
}
else {
    if ($env:LANG -like 'zh[-_]CN*') {
        $PSCompletions.lang = 'zh-CN'
    }
    else {
        $PSCompletions.lang = 'en-US'
    }
}
$PSCompletions.langs = @('zh-CN', 'en-US')
$PSCompletions.comp_data = [ordered]@{}
$PSCompletions.comp_config = @{}

@('config', 'confirm', 'download', 'less', 'order', 'text') | ForEach-Object {
    . $PSScriptRoot\utils\$_.ps1
}

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler 'Tab' MenuComplete
}
if (!(Test-Path($PSCompletions.path.completions))) {
    New-Item -ItemType Directory $PSCompletions.path.completions > $null
}
if (!(Test-Path($PSCompletions.path.list)) -or !(Test-Path($PSCompletions.path.root + '/env.json'))) {
    if ([environment]::GetEnvironmentvariable('abgox_PSCompletions', 'User')) {
        [environment]::SetEnvironmentvariable('abgox_PSCompletions', '', 'User')
    }
    #region move old completions
    $version = (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent)).Name | Sort-Object { [Version] $_ } -ErrorAction SilentlyContinue
    if ($version -is [array]) { $version = $version[-2] }
    $old_version_dir = (Split-Path $PSCompletions.path.root -Parent) + '\' + $version
    $old = (Get-ChildItem ($old_version_dir + '\' + 'completions') -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -ne 'PSCompletions' }).FullName
    if ($old) { Move-Item $old $PSCompletions.path.completions -Force -ErrorAction SilentlyContinue }
    if (Test-Path($old_version_dir + '\env.json')) {
        Move-Item ($old_version_dir + '\env.json') ($PSCompletions.path.root + '\env.json') -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path($old_version_dir + '\config.json')) {
        Move-Item ($old_version_dir + '\config.json') ($PSCompletions.path.root + '\config.json') -Force -ErrorAction SilentlyContinue
    }
    #endregion

    #region init env
    $config = $PSCompletions.fn_get_config()
    if ($config.root_cmd) {
        $new_config = @{
            root_cmd = $config.root_cmd
            github   = $config.github
            gitee    = $config.gitee
            language = $config.language
            update   = 1
            LRU      = $config.LRU
        }
    }
    else {
        $new_config = @{
            root_cmd = 'psc'
            github   = 'https://github.com/abgox/PSCompletions'
            gitee    = 'https://gitee.com/abgox/PSCompletions'
            language = $PSCompletions.lang
            update   = 1
            LRU      = 5
        }
    }
    $new_config | ConvertTo-Json | Out-File "$($PSCompletions.path.root)/env.json"
    #endregion

    $PSCompletions.init = $true
}

$PSCompletions | Add-Member -MemberType ScriptMethod fn_init {
    $PSCompletions.comp_cmd = [ordered]@{}
    $PSCompletions.config = $PSCompletions.fn_get_config()
    $PSCompletions.root_cmd = $PSCompletions.config.root_cmd

    if ($PSCompletions.config.language) {
        $PSCompletions.lang = $PSCompletions.config.language
    }
    if ($PSCompletions.config.github) {
        $PSCompletions.github = $PSCompletions.config.github.Replace('github.com', 'raw.githubusercontent.com') + '/main'
    }
    if ($PSCompletions.config.gitee) {
        $PSCompletions.gitee = $PSCompletions.config.gitee + '/raw/main'
    }
    function _do($i, $k) {
        if ($PSCompletions.config.$i) { return @($PSCompletions.$i, $PSCompletions.config.$i) }
        else { return @($PSCompletions.$k, $PSCompletions.config.$k) }
    }
    if ($PSCompletions.lang -eq 'zh-CN') {
        $info = _do 'gitee' 'github'
        $PSCompletions.url = $info[0]
        $PSCompletions.repo = $info[1]
    }
    else {
        $info = _do 'github' 'gitee'
        $PSCompletions.url = $info[0]
        $PSCompletions.repo = $info[1]
        $PSCompletions.lang = 'en-US'
    }

    $psc_alias_path = $PSCompletions.path.completions + '\PSCompletions\alias.txt'
    $psc_json_path = $PSCompletions.path.completions + '\PSCompletions\lang\' + $PSCompletions.lang + '.json'

    try {
        if (!(Test-Path($psc_json_path))) {
            $psc_temp = 'PSCompletion.json'
            Invoke-WebRequest -Uri ($PSCompletions.url + '/completions/PSCompletions/lang/' + $PSCompletions.lang + '.json') -OutFile $psc_temp
            $PSCompletions.json = (Get-Content -Path $psc_temp -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue).PSCompletions_core_info
            $PSCompletions.fn_add_completion('PSCompletions')
            Remove-Item $psc_temp -Force -ErrorAction SilentlyContinue
        }
        if (!(Test-Path($psc_alias_path))) {
            $PSCompletions.root_cmd | Out-File $psc_alias_path -Force -Encoding utf8
        }
        $psc_alias = (Get-Content $psc_alias_path -Raw -Encoding utf8).Trim()
        if ($psc_alias -ne $PSCompletions.root_cmd) {
            $PSCompletions.fn_set_config('root_cmd', $psc_alias)
            $PSCompletions.root_cmd = $PSCompletions.config.root_cmd = $psc_alias
        }
        $PSCompletions.json = (Get-Content -Path $psc_json_path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue).PSCompletions_core_info
        if (!(Test-Path($PSCompletions.path.update))) {
            New-Item $PSCompletions.path.update > $null
        }
        if (!(Test-Path($PSCompletions.path.list))) {
            New-Item $PSCompletions.path.list > $null
            if (!($PSCompletions.fn_download_list())) { throw }
        }
        if (!(Test-Path($PSCompletions.path.old_list))) {
            Copy-Item $PSCompletions.path.list $PSCompletions.path.old_list -Force
        }
        $PSCompletions.list = $PSCompletions.fn_get_content($PSCompletions.path.list)
        $PSCompletions.update = $PSCompletions.fn_get_content($PSCompletions.path.update)
    }
    catch { throw $PSCompletions.fn_replace($PSCompletions.json.init_err) }

    $res = [System.Collections.Generic.List[string]]@()
    $PSCompletions.installed = Get-ChildItem -Path $PSCompletions.path.completions -Filter '*.ps1' -Recurse -Depth 1 | Sort-Object CreationTime
    $PSCompletions.installed | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        $PSCompletions.comp_cmd.$cmd = $cmd
        $res.Add($_.FullName)
    }
    Get-ChildItem -Path $PSCompletions.path.completions -Filter 'alias.txt' -Recurse -Depth 1 | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent)  -Leaf
        $PSCompletions.comp_cmd.$cmd = (Get-Content $_.FullName -Raw).Trim()
    }
    $load_err_list = [System.Collections.Generic.List[string]]@()
    foreach ($item in $res) {
        try { . $item }catch { $load_err_list.Add($item) }
    }
    if ($load_err_list) {
        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.import_error))
    }
}
$PSCompletions.fn_init()

if ($PSHOME -notlike "*WindowsPowerShell*" -and $PSVersionTable.Platform -ne 'Unix') {
    $PSCompletions.path.config = $PSCompletions.path.root + '\config.json'
    $PSCompletions.ui = [ordered]@{}
    . $PSScriptRoot\ui\ui.ps1
}

$PSCompletions.comp_cmd.keys | Where-Object { $PSCompletions.comp_cmd.$_ -ne $_ } | ForEach-Object { Set-Alias $PSCompletions.comp_cmd.$_ $_ }

if (!$PSCompletions.config.github -and !$PSCompletions.config.gitee) {
    $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.repo_err))
}

#region init and update
if ($PSCompletions.init) { $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.init_info)) }

if ($PSCompletions.config.update -ne 0) {
    if ($PSCompletions.config.update -ne 1) {
        $null = $PSCompletions.fn_confirm($PSCompletions.json.module_update, {
                try {
                    $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.module_updating))
                    Update-Module PSCompletions
                    $version_list = (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent)).BaseName
                    if ($PSCompletions.config.update -in $version_list) {
                        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.module_update_done))
                    }
                    else {
                        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.module_update_err))
                    }
                }
                catch {
                    $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.module_update_err))
                }
            })
    }
    else {
        $add = $PSCompletions.fn_get_content($PSCompletions.path.core + '\.add')
        if ($PSCompletions.update -or $add) {
            $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.update_info))
        }
    }
}
#endregion

$PSCompletions.jobs = Start-Job -ScriptBlock {
    param( $PSCompletions, $path_history )
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
            $json = Get-Content -Raw -Path ($PSScriptRoots + '\lang\' + $PSCompletions.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
            $i = 1
            $res = [ordered]@{}
            $json.PSObject.Properties.Name | Where-Object {
                $_ -notin $exclude
            } | ForEach-Object {
                $res.$_ = $i
                $i++
            }
            $res | ConvertTo-Json | Out-File $path_order -Force
        }
        return (Get-Content -Raw $path_order -Encoding utf8 | ConvertFrom-Json)
    }

    $alias_list = $PSCompletions.comp_cmd.Keys | ForEach-Object { $PSCompletions.comp_cmd.$_ }
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
    $PSCompletions.comp_cmd.Keys | ForEach-Object {
        $alias = $PSCompletions.comp_cmd.$_
        $cmd_list.$alias = $_
    }

    $cache[ - ([int]$PSCompletions.config.LRU)..-1] | ForEach-Object {
        $cmd_list.$_
    } | ForEach-Object {
        $alias = $PSCompletions.comp_cmd.$_
        $PSCompletions.comp_data.$alias = @{}
        if ($PSCompletions.comp_config.$_.language) {
            $lang = $PSCompletions.comp_config.$_.language
        }
        else {
            $lang = $PSCompletions.lang
        }

        $json = Get-Content -Raw -Path  "$($PSCompletions.path.completions)\$($_)\lang\$($lang).json" -Encoding UTF8 | ConvertFrom-Json

        $info = $_ + '_core_info'
        $PSCompletions.comp_data.$($alias + '_info') = @{
            core_info = $json.$info
            exclude   = @($info)
            num       = -1
        }

        $order = get_order ($PSCompletions.path.completions + '\' + $_) $PSCompletions.comp_data.$($alias + '_info').exclude

        $_i = 1
        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $PSCompletions.comp_data.$($alias + '_info').exclude
        } | ForEach-Object {
            $cmd = $_ -split ' '
            $_o = if ($order.$_) { $order.$_ }else { $_i }
            $PSCompletions.comp_data.$alias[$alias + ' ' + $_] = @($cmd[-1], $json.$_, $_o)
            $_i++
        }
    }
    return $PSCompletions.comp_data
} -ArgumentList $PSCompletions, (Get-PSReadLineOption).HistorySavePath

$null = Start-Job -ScriptBlock {
    param( $PSCompletions )
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
            if ($PSCompletions.url) {
                $res = Invoke-WebRequest -Uri ($PSCompletions.url + '/list.txt')
                if ($res.StatusCode -eq 200) {
                    $content = $res.Content.Trim()
                    $old_list = Get-Content $PSCompletions.path.old_list -Raw -Encoding utf8
                    $list = Get-Content $PSCompletions.path.list -Raw -Encoding utf8
                    if ($old_list -ne $list) {
                        Copy-Item $PSCompletions.path.list $PSCompletions.path.old_list -Force
                    }
                    if ($content -ne $list.Trim()) {
                        $content | Out-File $PSCompletions.path.list -Force -Encoding utf8
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
        $c = Get-Content -raw -path "$($PSCompletions.path.root)/env.json" | ConvertFrom-Json
        return @{
            root_cmd = $c.root_cmd
            github   = $c.github
            gitee    = $c.gitee
            language = $c.language
            update   = $c.update
            LRU      = $c.LRU
        }
    }
    function set_config([string]$k, [string]$v) {
        $c = get_config
        $c.$k = $v
        $c | ConvertTo-Json | Out-File "$($PSCompletions.path.root)/env.json"
    }
    _do {
        $response = Invoke-WebRequest -Uri ($PSCompletions.url + '/module/.version')
        if ($response.StatusCode -eq 200) {
            $content = $response.Content.Trim()
            $versions = @($PSCompletions.version, $content) | Sort-Object { [Version] $_ }
            if ($versions[-1] -ne $PSCompletions.version) {
                $res = Invoke-WebRequest -Uri ($PSCompletions.url + '/module/log.json')
                if ($res.StatusCode -eq 200) {
                    $res.Content | Out-File ($PSCompletions.path.core + '\log.json') -Force -Encoding utf8
                    set_config 'update' $versions[-1]
                }
            }
        }
    }

    $old_list = Get-Content $PSCompletions.path.old_list -Encoding utf8
    $new_list = Get-Content $PSCompletions.path.list -Encoding utf8
    $diff = Compare-Object $new_list $old_list -PassThru
    if ($diff) {
        $diff | Out-File ($PSCompletions.path.core + '\.add') -Force -Encoding utf8
    }

    download_list

    $update_list = [System.Collections.Generic.List[string]]@()
    $installed = (Get-ChildItem -Path $PSCompletions.path.completions -Filter '*.ps1' -Recurse -Depth 1).BaseName | Where-Object { $_ -in $PSCompletions.list }

    $installed | ForEach-Object {
        $url = $PSCompletions.url + '/completions/' + $_ + '/guid.txt'
        $response = Invoke-WebRequest -Uri  $url
        if ($response.StatusCode -eq 200) {
            $content = $response.Content.Trim()
            $guid = (Get-Content ($PSCompletions.path.completions + '\' + $_ + '\guid.txt') -Raw).Trim()
            if ($guid -ne $content) { $update_list.Add($_) }
        }
    }
    $old_update_list = Get-Content $PSCompletions.path.update -Encoding utf8

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
        $update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8
    }
} -ArgumentList $PSCompletions
