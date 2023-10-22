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
$root_dir = Split-Path $PSScriptRoot -Parent
$comp_dir = $root_dir + '\completions\' + $comp_name

if ($comp_name.Trim()) {
    if (Test-Path($comp_dir)) {
        throw (info).exist
    }
    else {
        mkdir $comp_dir > $null

        function _replace($in, $out) {
            $parent = Split-Path $out -Parent
            if (!(Test-Path($parent))) {
                mkdir $parent > $null
            }
            (Get-Content -Raw "$PSScriptRoot\$in").Replace('$template_comp', "$comp_name") | Out-File $out -Encoding utf8
        }
        _replace "template\template.ps1" "$comp_dir\$comp_name.ps1"
        _replace "template\json\zh-CN.json" "$comp_dir\json\zh-CN.json"
        _replace "template\json\en-US.json" "$comp_dir\json\en-US.json"
        (New-Guid).Guid | Out-File "$comp_dir\.guid"

        Write-Host "`n$comp_dir\$comp_name.ps1" -f Green
    }
}
