. $PSScriptRoot\utils.ps1
$_psc = @{}
$_psc.version = '2.0.9'
$_psc.path = @{}
$_psc.path.root = Split-Path $PSScriptRoot -Parent
$_psc.path.completions = $_psc.path.root + '\completions'
$_psc.path.core = $_psc.path.root + '\core'
$_psc.path.list = $_psc.path.root + '\list.txt'
$_psc.path.old_list = $_psc.path.core + '\.old_list'
$_psc.path.update = $_psc.path.core + '\.update'
$_psc.path.psc_alias = $_psc.path.completions + '\PSCompletions\.alias'
$_psc.lang = (Get-WinSystemLocale).name
$_psc.langs = @('zh-CN', 'en-US')

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
    $_psc.comp_cmd = [ordered]@{}
    $_psc.config = _psc_get_config
    $_psc.root_cmd = $_psc.config.root_cmd

    if ($_psc.config.language) {
        $_psc.lang = $_psc.config.language
    }
    if ($_psc.lang -ne 'zh-CN') {
        $_psc.lang = 'en-US'
    }
    if ($_psc.config.github) {
        $_psc.github = $_psc.config.github.Replace('github.com', 'raw.githubusercontent.com') + '/main'
    }
    if ($_psc.config.gitee) {
        $_psc.gitee = $_psc.config.gitee + '/raw/main'
    }
    function _do($i, $k) {
        if ($_psc.config.$i) {
            return @($_psc.$i, $_psc.config.$i)
        }
        else {
            return @($_psc.$k, $_psc.config.$k)
        }
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
    }

    $psc_json_path = $_psc.path.completions + '\PSCompletions\json\' + $_psc.lang + '.json'

    try {
        if ($_psc.init) {
            $psc_temp = $env:TEMP + '\PSCompletion.json'
            Invoke-WebRequest -Uri ($_psc.url + '/completions/PSCompletions/json/' + $_psc.lang + '.json') -OutFile $psc_temp
            $_psc.json = (Get-Content -Path $psc_temp -Raw -Encoding UTF8 | ConvertFrom-Json).PSCompletions_core_info
        }
        if (!(Test-Path($psc_json_path))) {
            _psc_add_completion 'PSCompletions'
        }
        if (!(Test-Path($_psc.path.psc_alias))) {
            $_psc.root_cmd | Out-File $_psc.path.psc_alias -Force -Encoding utf8
        }
        $psc_alias = (Get-Content $_psc.path.psc_alias -Raw -Encoding utf8).Trim()
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
            if (!(_psc_download_list)) { return }
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

    $res = [System.Collections.Generic.List[string]]@()
    $_psc.installed = Get-ChildItem -Path $_psc.path.completions -Filter "*.ps1" -Recurse -Depth 1 | Sort-Object CreationTime
    $_psc.installed | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
        $_psc.comp_cmd.$cmd = $cmd
        $res.Add($_.FullName)
    }
    Get-ChildItem -Path $_psc.path.completions -Filter ".alias" -Recurse -Depth 1 | ForEach-Object {
        $cmd = Split-Path (Split-Path $_.FullName -Parent)  -Leaf
        $_psc.comp_cmd.$cmd = (Get-Content $_.FullName -Raw).Trim()
    }
    $res | ForEach-Object { . $_ }
}

PSCompletions_init

$_psc.comp_cmd.keys | Where-Object { $_psc.comp_cmd.$_ -ne $_ } | ForEach-Object { Set-Alias $_psc.comp_cmd.$_ $_ }

if (!$_psc.config.github -and !$_psc.config.gitee) {
    Write-Host (_psc_replace $_psc.json.repo_err) -f Yellow
}

#region init and update
if ($_psc.init) { Write-Host (_psc_replace $_psc.json.init_info) -f DarkCyan }
if ($_psc.config.update -ne 0) {
    if ($_psc.config.update -ne 1) {
        _psc_confirm $_psc.json.module_update {
            try {
                Write-Host (_psc_replace $_psc.json.module_updating) -f Cyan
                Update-Module 'PSCompletions'
                $version_list = (Get-ChildItem (Split-Path $_psc.path.root -Parent)).BaseName
                if ($_psc.config.update -in $version_list) {
                    Write-Host (_psc_replace $_psc.json.module_update_done) -f Green
                }
                else {
                    Write-Host (_psc_replace $_psc.json.module_update_err) -f Red
                }
            }
            catch {
                Write-Host (_psc_replace $_psc.json.module_update_err) -f Red
            }
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
        $response = Invoke-WebRequest -Uri ($_psc.url + '/module/.version')
        if ($response.StatusCode -eq 200) {
            $content = ($response.Content).Trim()
            $versions = @($_psc.version, $content) | Sort-Object { [Version] $_ }
            if ($versions[-1] -ne $_psc.version) {
                set_config 'update' $versions[-1]
                $res = Invoke-WebRequest -Uri ($_psc.url + '/module/log.json')
                if ($res.StatusCode -eq 200) {
                    $res.Content | Out-File ($_psc.path.core + '\log.json') -Force -Encoding utf8
                }
            }
        }
    }

    (Compare-Object -ReferenceObject (get_content $_psc.path.list) -DifferenceObject (get_content $_psc.path.old_list) -PassThru) | Out-File ($_psc.path.core + '\.add') -Force -Encoding utf8

    _do {
        $response = Invoke-WebRequest -Uri ($_psc.url + '/list.txt')
        if ($response.StatusCode -eq 200) {
            Move-Item  $_psc.path.list  $_psc.path.old_list -Force
            $response.Content | Out-File $_psc.path.list -Force -Encoding utf8
        }
    }

    $update_list = [System.Collections.Generic.List[string]]@()
    $installed = (Get-ChildItem -Path $_psc.path.completions -Filter "*.ps1" -Recurse -Depth 1).BaseName
    foreach ($_ in $installed) {
        $url = $_psc.url + '/completions/' + $_ + '/.guid'
        $response = Invoke-WebRequest -Uri  $url
        if ($response.StatusCode -eq 200) {
            $content = ($response.Content).Trim()
            $guid = (Get-Content ($_psc.path.completions + '\' + $_ + '\.guid') -Raw).Trim()
            if ($guid -ne $content) { $update_list.Add($_) }
        }
    }
    $update_list | Out-File $_psc.path.update -Force -Encoding utf8
} -ArgumentList $_psc
