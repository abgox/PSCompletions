function info($comp = $comp_name) {
    if ($PSCompletions.config.language) {
        $lang = $PSCompletions.config.language
    }
    else {
        $lang = (Get-WinSystemLocale).name
    }
    if ($lang -eq 'zh-CN') {
        return @{
            "input"          = "输入补全名称: "
            "exist"          = "$comp 补全文件已经存在!"
            "is_more_option" = '补全中是否有许多以 - 开头的选项?(y/n)'
            "test"           = "是否移动到模块下进行测试?(y/n)"
        }
    }
    else {
        return @{
            "input"          = 'New completion name: '
            "exist"          = "$comp already exists!"
            'is_more_option' = 'Is there many options with - prefix?(y/n)'
            "test"           = "Move to module for testing?(y/n)"
        }
    }
}

function get_input($tip, $default = '') {
    $res = $tip
    Write-Host -ForegroundColor Gray -NoNewline $res
    $inputs = Read-Host
    if (!$inputs.Trim()) {
        return $default
    }
    return $inputs
}

$comp_name = get_input (info).input
$root_dir = Split-Path $PSScriptRoot -Parent
$comp_dir = $root_dir + '\completions\' + $comp_name

$is_more_option = get_input (info).is_more_option 'y'

if ($comp_name.Trim()) {
    if (Test-Path($comp_dir)) {
        throw (info).exist
    }
    else {
        New-Item -ItemType Directory $comp_dir > $null

        function _replace($in, $out) {
            $parent = Split-Path $out -Parent
            if (!(Test-Path($parent))) {
                New-Item -ItemType Directory $parent > $null
            }
            (Get-Content -Raw "$PSScriptRoot\$in").Replace('$template_comp', "$comp_name") | Out-File $out -Encoding utf8
        }
        if ($is_more_option -eq 'y') {
            _replace "template\template2.ps1" "$comp_dir\$comp_name.ps1"
        }
        else {
            _replace "template\template.ps1" "$comp_dir\$comp_name.ps1"
        }
        _replace "template\lang\zh-CN.json" "$comp_dir\lang\zh-CN.json"
        _replace "template\lang\en-US.json" "$comp_dir\lang\en-US.json"
        (New-Guid).Guid | Out-File "$comp_dir\guid.txt"

        if ((get_input (info).test 'y') -eq 'y') {
            $completions_dir = Split-Path (PSCompletions which PSCompletions) -Parent
            Move-Item ("$PSScriptRoot\..\completions\$comp_name") $completions_dir
        }
        else {
            Write-Host "`n$comp_dir\$comp_name.ps1" -f Green
        }
    }
}
