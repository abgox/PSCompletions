. $PSScriptRoot\utils.ps1
$_psc = @{}
$_psc.version = '2.0.1'
$_psc.path = @{}
$_psc.path.root = Split-Path $PSScriptRoot -Parent
$_psc.path.completions = $_psc.path.root + '\completions'
$_psc.path.core = $_psc.path.root + '\core'
$_psc.path.list = $_psc.path.core + '\.list'
$_psc.path.old_list = $_psc.path.core + '\.old_list'
$_psc.path.update = $_psc.path.core + '\.update'
$_psc.lang = (Get-WinSystemLocale).name
$_psc.langs = @('zh-CN', 'en-US')
$_psc.comp_cmd = @{}

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler 'Tab' MenuComplete
}

if (!(Test-Path($_psc.path.list)) -or ([environment]::GetEnvironmentvariable("abgox_PSCompletions", "User") -split ';')[0] -ne $_psc.version) {
    if (!(Test-Path($_psc.path.completions))) {
        mkdir $_psc.path.completions > $null
    }

    #region move old completions
    $version = (Get-ChildItem (Split-Path $_psc.path.root -Parent)).Name | Sort-Object { [Version] $_ } -ErrorAction SilentlyContinue
    if ($version -is [array]) { $version = $version[-2] }
    $old = (Get-ChildItem ((Split-Path $_psc.path.root -Parent) + '\' + $version + '\' + 'completions') -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -ne 'PSCompletions' }).FullName
    if ($old) { Move-Item $old $_psc.path.completions -Force -ErrorAction SilentlyContinue }
    #endregion

    #region init env
    $config = _psc_get_config
    if ($config.module_version) {
        $root_cmd = $config.root_cmd
        $github = $config.github
        $gitee = $config.gitee
        $language = $config.language
        $update = if ($config.update -eq 0) { 0 } else { 1 }
    }
    else {
        $root_cmd = 'psc'
        $github = 'https://github.com/abgox/PSCompletions'
        $gitee = 'https://gitee.com/abgox/PSCompletions'
        $language = $_psc.lang
        $update = 1
    }
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', (@($_psc.version, $root_cmd, $github, $gitee, $language, $update) -join ';'), 'User')
    #endregion

    $_psc.init = $true
}

function PSCompletions_init() {
    $_psc.config = _psc_get_config
    $_psc.root_cmd = $_psc.config.root_cmd

    if ($_psc.config.language) {
        $_psc.lang = $_psc.config.language
    }
    if (!( $_psc.lang -in $_psc.langs)) {
        $_psc.lang = 'en-US'
    }

    $_psc.github = $_psc.config.github.Replace('github.com', 'raw.githubusercontent.com') + '/main'
    $_psc.gitee = $_psc.config.gitee + '/raw/main'

    function _do($i, $k) {
        return $(if ($_psc.config.$i) { $_psc.$i } else { $_psc.$k })
    }
    $_psc.url = if ($_psc.lang -eq 'zh-CN') { _do 'gitee' 'github' }else { _do 'github' 'gitee' }
    $_psc.repo = if ($_psc.lang -eq 'zh-CN') { $_psc.config.gitee }else { $_psc.config.github }

    $psc_json_path = $_psc.path.completions + '\PSCompletions\json\' + $_psc.lang + '.json'
    $psc_alias_path = $_psc.path.completions + '\PSCompletions\.alias'

    try {
        if ($_psc.init) {
            $psc_temp = $env:TEMP + '\PSCompletion.json'
            Invoke-WebRequest -Uri ($_psc.url + '/completions/PSCompletions/json/' + $_psc.lang + '.json') -OutFile $psc_temp
            $_psc.json = (Get-Content -Path $psc_temp -Raw -Encoding UTF8 | ConvertFrom-Json).PSCompletions_core_info
        }

        if (!(Test-Path($psc_json_path))) {
            _psc_add_completion 'PSCompletions'
        }
        if (!(Test-Path($psc_alias_path))) {
            $_psc.root_cmd | Out-File $psc_alias_path -Force
        }

        $psc_alias = (Get-Content $psc_alias_path -Raw -Encoding utf8).Trim()
        if ($psc_alias -ne $_psc.root_cmd) {
            _psc_set_config 'root_cmd' $psc_alias
            $_psc.root_cmd = $_psc.config.root_cmd = $psc_alias
        }
        $_psc.json = (Get-Content -Path $psc_json_path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue).PSCompletions_core_info

        if (!(Test-Path($_psc.path.update))) {
            New-Item $_psc.path.update > $null
        }
        if (!(Test-Path($_psc.path.list))) {
            New-Item $_psc.path.list > $null
            _psc_download_list
        }
        if (!(Test-Path($_psc.path.old_list))) {
            Copy-Item $_psc.path.list $_psc.path.old_list -Force -ErrorAction SilentlyContinue
        }
        $_psc.list = _psc_get_content $_psc.path.list
        $_psc.update = _psc_get_content $_psc.path.update
    }
    catch {
        if ($_psc.json.init_err) {
            throw (_psc_replace $_psc.json.init_err)
        }
        else {
            throw 'Init error due to possible network issues.'
        }
    }

    $res = @()
    $_psc.installed = Get-ChildItem -Path $_psc.path.completions -Filter "*.ps1" -Recurse -Depth 1
    $_psc.installed | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        $_psc.comp_cmd.$cmd = $cmd
        $res += $_.FullName
    }
    Get-ChildItem -Path $_psc.path.completions -Filter ".alias" -Recurse -Depth 1 | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent)  -Leaf
        $_psc.comp_cmd.$cmd = (Get-Content $_.FullName -Raw).Trim()
    }
    $res | ForEach-Object { . $_ }
}

PSCompletions_init

$_psc.comp_cmd.keys | Where-Object { $_psc.comp_cmd.$_ -ne $_ } | ForEach-Object { Set-Alias $_psc.comp_cmd.$_ $_ }

#region init and update
if ($_psc.init) { Write-Host (_psc_replace $_psc.json.init_info) -f DarkCyan }
if ($_psc.config.update -ne 0) {
    if ($_psc.config.update -ne 1) {
        _psc_confirm $_psc.json.module_update {
            Write-Host (_psc_replace $_psc.json.module_updating) -f Cyan
            Update-Module 'PSCompletions'
            Write-Host (_psc_replace $_psc.json.module_update_done) -f Green
        }
    }
    else {
        $add = _psc_get_content ($_psc.path.core + '\.add')
        if ($_psc.update -or $add) {
            Write-Host (_psc_replace $_psc.json.update_info ) -f Cyan
            if ($add) {
                Write-Host (_psc_replace $_psc.json.update_info_add) -f Cyan
            }
            if ($_psc.update) {
                Write-Host (_psc_replace $_psc.json.update_info_modify) -f Cyan
            }
            Write-Host (_psc_replace $_psc.json.update_tip) -f Cyan
        }
    }
}
#endregion

$null = Start-Job -ScriptBlock {
    param( $_psc )
    function set_config($k, $v) {
        $config = $_psc.config
        $config.$k = $v
        $res = @($config.module_version, $config.root_cmd, $config.github, $config.gitee, $config.language, $config.update) -join ';'
        [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
    }
    function get_content($path) {
        return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue)
    }

    function _do($do) { try { & $do }catch {} }
    _do {
        $response = Invoke-WebRequest -Uri ($_psc.url + '/core/.version')
        if ($response.StatusCode -eq 200) {
            $content = ($response.Content).Trim()
            $versions = @($_psc.version, $content) | Sort-Object { [Version] $_ }
            if ($versions[-1] -ne $_psc.version) {
                set_config 'update' $versions[-1]
            }
        }
    }
    (Compare-Object -ReferenceObject (get_content $_psc.path.list) -DifferenceObject (get_content $_psc.path.old_list) -PassThru) | Out-File ($_psc.path.core + '\.add')

    _do {
        $response = Invoke-WebRequest -Uri ($_psc.url + '/core/.list')
        if ($response.StatusCode -eq 200) {
            Move-Item  $_psc.path.list  $_psc.path.old_list -Force
            $response.Content | Out-File $_psc.path.list -Force
        }
    }

    $update_list = @()
    $installed = (Get-ChildItem -Path $_psc.path.completions -Filter "*.ps1" -Recurse -Depth 1).BaseName
    foreach ($_ in $installed) {
        $url = $_psc.url + '/completions/' + $_ + '/.guid'
        $response = Invoke-WebRequest -Uri  $url
        if ($response.StatusCode -eq 200) {
            $content = ($response.Content).Trim()
            $guid = (Get-Content ($_psc.path.completions + '\' + $_ + '\.guid') -Raw).Trim()
            if ($guid -ne $content) { $update_list += $_ }
        }
    }
    $update_list | Out-File $_psc.path.update -Force
} -ArgumentList $_psc
