. $PSScriptRoot\function.ps1
$_psc = @{}
function psc_init() {
    $is_init_first = $false
    $_psc.test = $is_init_first
    $_psc.list = ''
    $_psc.config = _psc_get_config
    $p_c = $_psc.config

    # 模块目录
    $_psc.root_dir = Split-Path $PSScriptRoot -Parent
    $_psc.completions = $_psc.root_dir + '\completions'
    $_psc.core = $_psc.root_dir + '\core'
    if (!(Test-Path($_psc.core + '\.list'))) {
        $root_cmd = 'psc'
        $github = 'https://github.com/abgox/PSCompletions'
        $gitee = 'https://gitee.com/abgox/PSCompletions'
        $language = ''
        $update = 7
        $guid = ''
        $time = [math]::Round((Get-Date -UFormat %s))
        [environment]::SetEnvironmentvariable('abgox_PSCompletions', ($root_cmd + ';' + $github + ';' + $gitee + ';' + $language + ';' + $update + ';' + $guid + ';' + $time), 'User')
        $is_init_first = $true
    }

    $_psc.lang = (Get-WinSystemLocale).name
    $_psc.langs = @('zh-CN', 'en-US')
    if ($p_c.language) {
        $_psc.lang = $p_c.language
    }
    if (!( $_psc.lang -in $_psc.langs)) {
        $_psc.lang = 'en-US'
    }

    $_psc.github = $p_c.github.Replace('github.com', 'raw.githubusercontent.com') + '/main'
    $_psc.gitee = $p_c.gitee + '/raw/main'
    function _do($var, $var2) {
        return $(if ($p_c.$var) { $_psc.$var } elseif ($p_c.$var2) { $_psc.$var2 })
    }
    if ($_psc.lang -eq 'zh-CN') {
        $_psc.url = _do 'gitee' 'github'
    }
    else {
        $_psc.url = _do 'github' 'gitee'
    }

    if (!(Test-Path($_psc.completions + '\PSCompletions\json\' + $_psc.lang + '.json'))) {
        _psc_add_completion 'PSCompletions' $false
    }
    $psc_alias_path = $_psc.completions + '\PSCompletions\.alias'
    if (!(Test-Path($psc_alias_path))) {
        echo $_psc.config.root_cmd > $psc_alias_path
    }
    $psc_alias = _psc_get_cmd ($_psc.completions + '\PSCompletions') 'psc'
    if ($psc_alias -ne ([environment]::GetEnvironmentvariable("abgox_PSCompletions", "User") -split ';')[0]) {
        _psc_set_config 'root_cmd' $psc_alias
    }

    $_psc.json = (Get-Content -Path  ($_psc.completions + '\PSCompletions\json\' + $_psc.lang + '.json') -Raw -Encoding UTF8 | ConvertFrom-Json).PSCompletions_core_info

    $_psc.list_path = $_psc.core + '\.list'
    $_psc.installed = Get-ChildItem -Path $_psc.completions -Filter "*.ps1" -Recurse

    if (!(Test-Path(($_psc.core + '\.update')))) {
        New-Item ($_psc.core + '\.update') > $null
    }

    if (!(Test-Path($_psc.list_path))) {
        _psc_download_list
    }
    function _do([scriptblock]$do) {
        try { & $do }catch {}
    }
    _do {
        if (!(Test-Path($_psc.core + '\.old_list'))) {
            Copy-Item $_psc.list_path ($_psc.core + '\.old_list') -Force
        }
    }
    _do { $_psc.list = _psc_get_content $_psc.list_path }

    if ($_psc.config.update -ne 0) {
        if ([math]::Round((Get-Date -UFormat %s)) - $_psc.config.time -gt [int]$_psc.config.update * 86400) {
            _psc_check_update > $null
        }
    }
    $_psc.update = (_psc_get_content ($_psc.core + '\.update')) -split ','

    if ($is_init_first -and (Test-Path($_psc.list_path))) {
        Write-Host (_psc_replace $_psc.json.init_info) -f DarkCyan
    }
    if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler 'Tab' MenuComplete
    }
    foreach ($_ in $_psc.installed) {
        . $_.FullName
    }
    return $is_init_first
}

$_psc_init_first = psc_init

if ($_psc.config.update -ne 0 -and !$_psc_init_first) {
    $compare = (Compare-Object -ReferenceObject $_psc.list -DifferenceObject (_psc_get_content ($_psc.core + '\.old_list')) -PassThru)

    if ($_psc.update -or $compare) {
        Write-Host (_psc_replace $_psc.json.update_has ) -f Cyan
        if ($compare) {
            Write-Host (_psc_replace $_psc.json.update_has1 @{'add_list' = $compare } ) -f Cyan
        }
        if ($_psc.update) {
            Write-Host (_psc_replace $_psc.json.update_has2 @{'update_list' = $_psc.update } ) -f Cyan
        }
        Write-Host (_psc_replace $_psc.json.update_tip) -f Cyan
    }

}
New-Alias $_psc.config.root_cmd 'PSCompletions'
