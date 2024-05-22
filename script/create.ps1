function _replace {
    param ($data, $separator = '')
    $data = ($data -join $separator)
    $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
    $matches = [regex]::Matches($data, $pattern)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
    }
    if ($data -match $pattern) { (_replace $data) }else { return $data }
}

function write_with_color {
    param([string]$str)
    $color_list = @()
    $str = $str -replace "`n", 'n&&_n_n&&'
    $str_list = $str -split '(<\@[^>]+>.*?(?=<\@|$))' | Where-Object { $_ -ne '' } | ForEach-Object {
        if ($_ -match '<\@([\s\w]+)>(.*)') {
            ($matches[2] -replace 'n&&_n_n&&', "`n") -replace '^<\@>', ''
            $color = $matches[1] -split ' '
            $color_list += @{
                color   = $color[0]
                bgcolor = $color[1]
            }
        }
        else {
            ($_ -replace 'n&&_n_n&&', "`n") -replace '^<\@>', ''
            $color_list += @{}
        }
    }
    $str_list = [array]$str_list
    for ($i = 0; $i -lt $str_list.Count; $i++) {
        $color = $color_list[$i].color
        $bgcolor = $color_list[$i].bgcolor
        if ($color) {
            if ($bgcolor) {
                Write-Host $str_list[$i] -f $color -b $bgcolor -NoNewline
            }
            else {
                Write-Host $str_list[$i] -f $color -NoNewline
            }
        }
        else {
            Write-Host $str_list[$i] -NoNewline
        }
    }
    Write-Host ''
}

$language = if ($PSUICulture -eq 'zh-CN') { $PSUICulture }else { 'en-US' }

$guide = Get-Content -Path "$($PSScriptRoot)/template/guide/$($language).json" -Encoding utf8 | ConvertFrom-Json

function get_input($tip, $default = '') {
    Write-Host -NoNewline $tip -f Blue
    $inputs = Read-Host
    if (!$inputs.Trim()) {
        return $default
    }
    return $inputs
}

$completion_name = get_input $guide.name

if (!$completion_name.Trim()) {
    write_with_color $guide.err.name
    return
}

$config = @{
    language = @('en-US', 'zh-CN')
}

$root_dir = Split-Path $PSScriptRoot -Parent
$completions_dir = $root_dir + '/completions/' + $completion_name

if (Test-Path $completions_dir) {
    write_with_color $guide.exist
    return
}

if (Get-Command | Where-Object { $_.Name -eq 'PSCompletions' }) {
    $needTest = $true
}
else {
    $needTest = $false
}

# create new completion
New-Item -ItemType Directory $completions_dir > $null
New-Item -ItemType Directory "$completions_dir/language" > $null
[System.Guid]::NewGuid().Guid | Out-File "$completions_dir\guid.txt" -Encoding utf8 -Force

Copy-Item "$($PSScriptRoot)/template/config.json" "$completions_dir/config.json" -Force

Copy-Item "$($PSScriptRoot)/template/language/en-US.json" "$completions_dir/language/en-US.json" -Force
Copy-Item "$($PSScriptRoot)/template/language/zh-CN.json" "$completions_dir/language/zh-CN.json" -Force


if ($needTest) {
    $module_completions_dir = Split-Path (PSCompletions which psc) -Parent
    $test_dir = Join-Path $module_completions_dir $completion_name
    if (Test-Path $test_dir) {
        Remove-Item $test_dir -Recurse -Force
    }
    New-Item -ItemType SymbolicLink -Path $test_dir -Target $completions_dir > $null
    write_with_color (_replace $guide.success)
}
