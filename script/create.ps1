function get_input($tip, $default) {
    if ($default) {
        $res = $tip + $default
    }
    else {
        $res = $tip
    }
    Write-Host -ForegroundColor Gray  -NoNewline $res
    $inputs = Read-Host
    if (!$inputs.Trim()) {
        return $inputs
    }
    return $inputs
}

function info($comp = $comp_name) {
    if ($_psc.config.language) {
        $lang = $_psc.config.language
    }
    else {
        $lang = (Get-WinSystemLocale).name
    }
    if ($lang -eq 'zh-CN') {
        return @{
            "input" = "输入补全名称: "
            "exist" = "$comp 补全文件已经存在!"
        }
    }
    else {
        return @{
            "input" = 'New completion name: '
            "exist" = "$comp already exists!"
        }
    }
}
$comp_name = get_input (info).input
$comps_dir = Split-Path $PSScriptRoot -Parent
$comp_dir = $comps_dir + '\completions\' + $comp_name

if ($comp_name.Trim()) {
    if (Test-Path($comp_dir)) {
        throw (info).exist
    }
    else {
        mkdir $comp_dir > $null
        Copy-Item ".\template\json" $comp_dir -Recurse
        (Get-Content -Raw ".\template\template.ps1").Replace('$template_comp', "$comp_name") | Out-File "$comp_dir\$comp_name.ps1" -Encoding utf8
        Write-Host "`n$comp_dir\$comp_name.ps1" -f Green
    }
}
