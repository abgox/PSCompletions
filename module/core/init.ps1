using namespace System.Management.Automation
using namespace System.Management.Automation.Language

New-Variable -Name PSCompletions -Value @{}  -Option Constant
@('config', 'confirm', 'download', 'less', 'order', 'text', 'path') | ForEach-Object {
    . $PSScriptRoot\utils\$_.ps1
}
$PSCompletions.version = '3.1.1'
$PSCompletions.path = @{}
$PSCompletions.path.root = Split-Path $PSScriptRoot -Parent
$PSCompletions.path.completions = Join-Path $PSCompletions.path.root 'completions'
$PSCompletions.path.core = Join-Path $PSCompletions.path.root 'core'
$PSCompletions.path.list = Join-Path $PSCompletions.path.root 'list.txt'
$PSCompletions.path.config = Join-Path $PSCompletions.path.root 'config.json'
$PSCompletions.path.old_list = Join-Path $PSCompletions.path.core '.old_list'
$PSCompletions.path.update = Join-Path $PSCompletions.path.core '.update'
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

if ($PSHOME -like "*WindowsPowerShell*" -and $PSCompletions.fn_get_config().run_with_admin -eq 1 -and (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    if ($PSCompletions.lang -eq 'zh-CN') {
        @(80, 83, 67, 111, 109, 112, 108, 101, 116, 105, 111, 110, 115, 32, 27169, 22359, 21152, 36733, 38169, 35823, 65306, 10, 30001, 20110, 20320, 20351, 29992, 30340, 26159, 32, 87, 105, 110, 100, 111, 119, 115, 32, 80, 111, 119, 101, 114, 83, 104, 101, 108, 108, 65292, 20320, 38656, 35201, 20351, 29992, 31649, 29702, 21592, 26435, 38480, 21551, 21160, 23427, 10, 25512, 33616, 20320, 20351, 29992, 32, 80, 111, 119, 101, 114, 83, 104, 101, 108, 108, 65292, 23427, 19981, 38656, 35201, 31649, 29702, 21592, 26435, 38480, 10) | ForEach-Object {
            $privilege_err += [char]::ConvertFromUtf32($_)
        }
        Write-Host $privilege_err -f Red
    }
    else {
        Write-Host "PSCompletions module loading err:`nBecause you're using Windows PowerShell, you must start it with administrator privilege.`nRecommend using PowerShell as it doesn't require administrator privilege.`n" -f Red
    }
    throw
}

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler 'Tab' MenuComplete
}
if (!(Test-Path $PSCompletions.path.completions)) {
    New-Item -ItemType Directory $PSCompletions.path.completions > $null
}
if (!(Test-Path $PSCompletions.path.list) -or !(Test-Path (Join-Path $PSCompletions.path.root 'env.json'))) {
    if ([environment]::GetEnvironmentvariable('abgox_PSCompletions', 'User')) {
        [environment]::SetEnvironmentvariable('abgox_PSCompletions', '', 'User')
    }
    #region move old completions
    $version = (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent)).Name | Sort-Object { [Version] $_ } -ErrorAction SilentlyContinue
    if ($version -is [array]) { $version = $version[-2] }
    $old_version_dir = Join-Path (Split-Path $PSCompletions.path.root -Parent) $version
    $old = (Get-ChildItem (Join-Path $old_version_dir 'completions') -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -ne 'PSCompletions' }).FullName
    if ($old) { Move-Item $old $PSCompletions.path.completions -Force -ErrorAction SilentlyContinue }
    if (Test-Path (Join-Path $old_version_dir 'env.json')) {
        Move-Item (Join-Path $old_version_dir 'env.json') (Join-Path $PSCompletions.path.root 'env.json') -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path (Join-Path $old_version_dir 'config.json')) {
        Move-Item (Join-Path $old_version_dir 'config.json') (Join-Path $PSCompletions.path.root 'config.json') -Force -ErrorAction SilentlyContinue
    }
    #endregion

    #region init env
    $PSCompletions.fn_get_config() | ConvertTo-Json | Out-File (Join-Path $PSCompletions.path.root 'env.json')
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

    $psc_alias_path = $PSCompletions.fn_join_path($PSCompletions.path.completions, 'PSCompletions', 'alias.txt')
    $psc_json_path = $PSCompletions.fn_join_path($PSCompletions.path.completions, 'PSCompletions', 'lang', ($PSCompletions.lang + '.json'))

    try {
        if (!(Test-Path $psc_json_path)) {
            $psc_temp = 'PSCompletions' + (New-Guid).Guid + '.json'
            $PSCompletions.wc = New-Object System.Net.WebClient
            $PSCompletions.wc.DownloadFile(($PSCompletions.url + '/completions/PSCompletions/lang/' + $PSCompletions.lang + '.json'), $psc_temp)
            $PSCompletions.json = ($PSCompletions.fn_get_raw_content($psc_temp) | ConvertFrom-Json -ErrorAction SilentlyContinue).PSCompletions_core_info
            $PSCompletions.fn_add_completion('PSCompletions')
            Remove-Item $psc_temp -Force -ErrorAction SilentlyContinue
        }
        if (!(Test-Path $PSCompletions.path.list)) {
            New-Item $PSCompletions.path.list > $null
            if (!($PSCompletions.fn_download_list())) { throw }
        }
    }
    catch { throw $PSCompletions.fn_replace($PSCompletions.json.init_err) }

    if (!(Test-Path $psc_alias_path)) {
        $PSCompletions.root_cmd | Out-File $psc_alias_path -Force -Encoding utf8
    }
    $psc_alias = $PSCompletions.fn_get_raw_content($psc_alias_path)
    if ($psc_alias) { $psc_alias = $psc_alias.Trim() }
    if ($psc_alias -ne $PSCompletions.root_cmd) {
        $PSCompletions.fn_set_config('root_cmd', $psc_alias)
        $PSCompletions.root_cmd = $PSCompletions.config.root_cmd = $psc_alias
    }
    $PSCompletions.json = ($PSCompletions.fn_get_raw_content($psc_json_path) | ConvertFrom-Json).PSCompletions_core_info
    if (!(Test-Path $PSCompletions.path.update)) {
        New-Item $PSCompletions.path.update > $null
    }
    if (!(Test-Path $PSCompletions.path.old_list)) {
        Copy-Item $PSCompletions.path.list $PSCompletions.path.old_list -Force
    }
    $PSCompletions.list = $PSCompletions.fn_get_content($PSCompletions.path.list)
    $PSCompletions.update = $PSCompletions.fn_get_content($PSCompletions.path.update)

    $res = [System.Collections.Generic.List[string]]@()
    $PSCompletions.installed = Get-ChildItem -Path $PSCompletions.path.completions -Filter '*.ps1' -Recurse -Depth 1 | Sort-Object CreationTime
    $PSCompletions.installed | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        $PSCompletions.comp_cmd.$cmd = $cmd
        $res.Add($_.FullName)
    }
    Get-ChildItem -Path $PSCompletions.path.completions -Filter 'alias.txt' -Recurse -Depth 1 | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent)  -Leaf
        $PSCompletions.comp_cmd.$cmd = $PSCompletions.fn_get_raw_content($_.FullName)
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

if (!$PSCompletions.ui -and $PSHOME -notlike "*WindowsPowerShell*" -and $PSVersionTable.Platform -ne 'Unix') {
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
        if ($PSCompletions.config.module_update -eq 1) {
            $null = $PSCompletions.fn_confirm($PSCompletions.json.module_update, {
                    try {
                        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.module_updating))
                        try {
                            Update-Module PSCompletions -ErrorAction Stop
                        }
                        catch {
                            $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.module_update_admin))
                            & "$($PSCompletions.path.core)\utils\sudo.ps1" Update-Module PSCompletions -ErrorAction Stop
                        }
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
    }
    else {
        $add = $PSCompletions.fn_get_content((Join-Path $PSCompletions.path.core '.add'))
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
    function get_raw_content([string]$path, [bool]$trim = $true) {
        $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        if ($trim -and $res) { return $res.Trim() }
        return $res
    }
    function get_order {
        param (
            [string]$PSScriptRoots,
            [array]$exclude = @(),
            [string]$file = 'order.json'
        )
        $path_order = Join-Path $PSScriptRoots $file

        if (!(Test-Path $path_order)) {
            $json = get_raw_content ($PSScriptRoots + '/lang/' + $PSCompletions.lang + '.json') | ConvertFrom-Json
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
        return (get_raw_content $path_order | ConvertFrom-Json)
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

        $json = get_raw_content "$($PSCompletions.path.completions)/$($_)/lang/$($lang).json" | ConvertFrom-Json

        $info = $_ + '_core_info'
        $PSCompletions.comp_data.$($alias + '_info') = @{
            core_info = $json.$info
            exclude   = @($info)
            num       = -1
        }
        $common_options = $json.$info.common_options
        $order = get_order ($PSCompletions.path.completions + '/' + $_) $PSCompletions.comp_data.$($alias + '_info').exclude

        $_i = 1
        $__i = 999999
        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $PSCompletions.comp_data.$($alias + '_info').exclude
        } | ForEach-Object {
            $cmd = $_ -split ' '
            $_o = if ($order.$_) { $order.$_ }else { $_i }
            $PSCompletions.comp_data.$alias[$alias + ' ' + $_] = @($cmd[-1], $json.$_, $_o)
            $_i++
            if ($common_options) {
                foreach ($item in $common_options.PSObject.Properties.Name) {
                    $PSCompletions.comp_data.$alias[$alias + ' ' + $_ + ' ' + $item] = @($item, $common_options.$item, $__i)
                    $__i ++
                }
            }
        }
        if ($common_options) {
            foreach ($item in $common_options.PSObject.Properties.Name) {
                $PSCompletions.comp_data.$alias[$alias + ' ' + $item] = @($item, $common_options.$item, $__i)
                $__i++
            }
        }
    }
    return $PSCompletions.comp_data
} -ArgumentList $PSCompletions, (Get-PSReadLineOption).HistorySavePath

$null = Start-Job -ScriptBlock {
    param( $PSCompletions )
    function _do($do) { try { & $do }catch {} }
    function get_content([string]$path) {
        return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' })
    }
    function get_raw_content([string]$path, [bool]$trim = $true) {
        $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        if ($trim -and $res) { return $res.Trim() }
        return $res
    }
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
                    $content = $res.Content -split "`n" | Where-Object { $_ -ne '' }
                    $old_list = get_content $PSCompletions.path.old_list
                    $list = get_content $PSCompletions.path.old_list
                    if (Compare-Object $list $old_list -PassThru) {
                        Copy-Item $PSCompletions.path.list $PSCompletions.path.old_list -Force
                    }
                    if (Compare-Object $content $list -PassThru) {
                        $content | Out-File $PSCompletions.path.list -Force -Encoding utf8
                        $PSCompletions.list = $PSCompletions.fn_get_content($PSCompletions.path.list)
                    }
                    return $content
                }
            }
            else { return $false }
        }
        catch { return $false }
    }
    function get_config() {
        $c = $PSCompletions.fn_get_raw_content("$($PSCompletions.path.root)/env.json") | ConvertFrom-Json

        $config = [ordered]@{}

        $default = [ordered]@{
            root_cmd       = 'psc'
            github         = 'https://github.com/abgox/PSCompletions'
            gitee          = 'https://gitee.com/abgox/PSCompletions'
            language       = $PSCompletions.lang
            update         = 1
            LRU            = 5
            run_with_admin = 1
            module_update  = 1
            sym            = [char]::ConvertFromUtf32(128516)
            sym_wr         = [char]::ConvertFromUtf32(128526)
            sym_opt        = [char]::ConvertFromUtf32(129300)
        }
        $need_set = $false
        foreach ($key in $default.Keys) {
            if ($key -notin $c.PSObject.Properties.Name) {
                $need_set = $true
                $config.$key = $default[$key]
            }
            else {
                $config.$key = $c.$key
            }
        }
        if ($need_set) {
            $config | ConvertTo-Json | Out-File "$($PSCompletions.path.root)/env.json"
        }
        if ($config.update -eq $PSCompletions.version) {
            $config.update = 1
        }
        return $config
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
                $PSCompletions.wc = New-Object System.Net.WebClient
                $log_url = $PSCompletions.url + '/module/log.json'
                $log_file = $PSCompletions.path.core + '/log.json'
                $PSCompletions.wc.DownloadFile($log_url, $log_file)
                if (Test-Path $log_file) {
                    set_config 'update' $versions[-1]
                }
            }
        }
    }

    $old_list = get_content $PSCompletions.path.old_list
    $new_list = get_content $PSCompletions.path.list
    $diff = Compare-Object $new_list $old_list -PassThru
    if ($diff) {
        $diff | Out-File ($PSCompletions.path.core + '/.add') -Force -Encoding utf8
    }
    else { Clear-Content ($PSCompletions.path.core + '/.add') -Force }

    download_list

    $update_list = [System.Collections.Generic.List[string]]@()
    $installed = (Get-ChildItem -Path $PSCompletions.path.completions -Filter '*.ps1' -Recurse -Depth 1).BaseName | Where-Object { $_ -in $PSCompletions.list }

    _do {
        $installed | ForEach-Object {
            $url = $PSCompletions.url + '/completions/' + $_ + '/guid.txt'
            $response = Invoke-WebRequest -Uri $url
            if ($response.StatusCode -eq 200) {
                $content = $response.Content.Trim()
                $guid = get_raw_content($PSCompletions.path.completions + '/' + $_ + '/guid.txt') $true
                if ($guid -ne $content) { $update_list.Add($_) }
            }
        }
    }
    $old_update_list = get_content $PSCompletions.path.update

    if ($update_list) {
        if ($old_update_list) {
            $is_write = Compare-Object $update_list $old_update_list -PassThru
        }
        else {
            $is_write = $true
        }
    }

    if ($is_write) {
        $update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8
    }
} -ArgumentList $PSCompletions
