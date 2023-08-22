. $PSScriptRoot\function.ps1
$_psc = @{}
$_psc.version = '1.1.4'
$_psc.root_dir = Split-Path $PSScriptRoot -Parent
$_psc.completions = $_psc.root_dir + '\completions'
$_psc.core = $_psc.root_dir + '\core'
$_psc.list_path = $_psc.core + '\.list'
$_psc.old_list_path = $_psc.core + '\.old_list'
$_psc.update_path = $_psc.core + '\.update'
$_psc.lang = (Get-WinSystemLocale).name
$_psc.langs = @('zh-CN', 'en-US')
$_psc.alias_path = $_psc.completions + '\PSCompletions\.alias'
$_psc.init = $false

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler 'Tab' MenuComplete
}

if (!(Test-Path($_psc.list_path)) -or ([environment]::GetEnvironmentvariable("abgox_PSCompletions", "User") -split ';')[0] -ne $_psc.version) {
    if (!(Test-Path($_psc.completions))) {
        mkdir $_psc.completions > $null
    }
    $_psc.versions_dir = (Get-ChildItem (Split-Path $_psc.root_dir -Parent)).Name | Sort-Object { [Version] $_ }
    if ($_psc.versions_dir -is [array]) {
        $_psc.versions_dir = $_psc.versions_dir[-2]
    }
    $_psc.old=(Get-ChildItem ((Split-Path $_psc.root_dir -Parent) + '\' + $_psc.versions_dir + '\' + 'completions') | Where-Object { $_.BaseName -ne 'PSCompletions' }).FullName
    if($_psc.old){
        Copy-Item $_psc.old $_psc.completions -Recurse -Force -ErrorAction SilentlyContinue
    }

    $config = _psc_get_config
    if ($config.root_cmd) {
        $module_version = $_psc.version
        $root_cmd = $config.root_cmd
        $github = $config.github
        $gitee = $config.gitee
        $language = $config.language
        if ($config.update -eq 0) { $update = 0 }else { $update = 1 }
    }
    else {
        $module_version = $_psc.version
        $root_cmd = _psc_get_cmd ($_psc.completions + '\PSCompletions') 'psc'
        $github = 'https://github.com/abgox/PSCompletions'
        $gitee = 'https://gitee.com/abgox/PSCompletions'
        $language = $_psc.lang
        $update = 1
    }
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', ($module_version + ';' + $root_cmd + ';' + $github + ';' + $gitee + ';' + $language + ';' + $update), 'User')
    $_psc.init = $true
}
function psc_init() {
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
    function _do($var, $var2) {
        return $(if ($_psc.config.$var) { $_psc.$var } elseif ($_psc.config.$var2) { $_psc.$var2 })
    }
    if ($_psc.lang -eq 'zh-CN') {
        $_psc.url = _do 'gitee' 'github'
    }
    else {
        $_psc.url = _do 'github' 'gitee'
    }
    $psc_json_path = $_psc.completions + '\PSCompletions\json\' + $_psc.lang + '.json'

    try {
        if ($_psc.init) {
            $psc_temp = $env:TEMP + '\PSCompletion.json'
            Invoke-WebRequest -Uri ($_psc.url + '/completions/PSCompletions/json/' + $_psc.lang + '.json') -OutFile $psc_temp
            $_psc.json = (Get-Content -Path $psc_temp -Raw -Encoding UTF8 | ConvertFrom-Json).PSCompletions_core_info
        }

        if (!(Test-Path($psc_json_path))) {
            _psc_add_completion 'PSCompletions'
        }
        if (!(Test-Path($_psc.alias_path))) {
            echo $_psc.config.root_cmd > $_psc.alias_path
        }
        $psc_alias = _psc_get_cmd ($_psc.completions + '\PSCompletions') 'psc'
        if ($psc_alias -ne $_psc.root_cmd) {
            _psc_set_config 'root_cmd' $psc_alias
            $_psc.root_cmd = $_psc.config.root_cmd = $psc_alias
        }
        $_psc.json = (Get-Content -Path $psc_json_path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Continue).PSCompletions_core_info

        if (!(Test-Path($_psc.update_path))) {
            New-Item $_psc.update_path > $null
        }
        if (!(Test-Path($_psc.list_path))) {
            New-Item $_psc.list_path > $null
            _psc_download_list
        }
        if (!(Test-Path($_psc.old_list_path))) {
            Copy-Item $_psc.list_path $_psc.old_list_path -Force -ErrorAction Continue
        }
        $_psc.list = _psc_get_content $_psc.list_path
        $_psc.update = (_psc_get_content $_psc.update_path)
    }
    catch {
        if ($_psc.json.init_error) {
            throw (_psc_replace $_psc.json.init_error)
        }
        else {
            throw 'Init error due to possible network issues.'
        }
    }
    $_psc.installed = Get-ChildItem -Path $_psc.completions -Filter "*.ps1" -Recurse
    $_psc.installed | ForEach-Object { . $_.FullName }
}

psc_init

if ($_psc.init -and (Test-Path($_psc.list_path))) {
    Write-Host (_psc_replace $_psc.json.init_info) -f DarkCyan
}

if ($_psc.config.update -notin @(1, 0)) {
    Write-Host (_psc_replace $_psc.json.module_update) -f Yellow
    $choice = $host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
    if ($choice.Character -eq 13) {
        Write-Host (_psc_replace $_psc.json.module_updating) -f Cyan
        Update-Module 'PSCompletions'
        Write-Host (_psc_replace $_psc.json.module_updated) -f Green
    }
    else {
        Write-Host (_psc_replace $_psc.json.module_cancel) -f Green
    }
}
if ($_psc.config.update -ne 0) {
    $add = _psc_get_content ($_psc.core + '\.add')
    if ($_psc.update -or $add) {
        Write-Host (_psc_replace $_psc.json.update_has ) -f Cyan
        if ($add) {
            Write-Host (_psc_replace $_psc.json.update_has1) -f Cyan
        }
        if ($_psc.update) {
            Write-Host (_psc_replace $_psc.json.update_has2) -f Cyan
        }
        Write-Host (_psc_replace $_psc.json.update_tip) -f Cyan
    }
}

New-Alias $_psc.root_cmd 'PSCompletions'

$null = Start-Job -ScriptBlock {
    param(
        $_psc,
        $get_config
    )
    $get_config = Get-Command $_psc_get_config -CommandType Function
    $_psc.config = &$get_config
    function set_config($key, $value) {
        $config = $_psc.config
        $config.$key = $value
        $res = $config.module_version + ';' + $config.root_cmd + ';' + $config.github + ';' + $config.gitee + ';' + $config.language + ';' + $config.update
        [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
    }
    function get_content($path) {
        try {
            return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue)
        }
        catch { return "" }
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
    echo (Compare-Object -ReferenceObject (get_content $_psc.list_path) -DifferenceObject (get_content $_psc.old_list_path) -PassThru) > ($_psc.core + '\.add')
    _do {
        $response = Invoke-WebRequest -Uri ($_psc.url + '/core/.list')
        if ($response.StatusCode -eq 200) {
            $content = ($response.Content).Trim()
            Move-Item  $_psc.list_path  $_psc.old_list_path -Force
            echo $content > $_psc.list_path
        }
    }
    $res = New-Object System.Collections.ArrayList
    $installed = (Get-ChildItem -Path $_psc.completions -Filter "*.ps1" -Recurse).BaseName
    foreach ($_ in $installed) {
        $url = $_psc.url + '/completions/' + $_ + '/.guid'
        $response = Invoke-WebRequest -Uri  $url
        if ($response.StatusCode -eq 200) {
            $content = ($response.Content).Trim()
            $guid = (get_content ($_psc.completions + '\' + $_ + '\.guid')).Trim()
            if ($guid -ne $content) { $res.Add($_) > $null }
        }
        echo $res > $_psc.update_path
    }
} -ArgumentList $_psc, '_psc_get_config'
