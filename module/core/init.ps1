using namespace System.Management.Automation
# 创建一个常量对象，用于存储 PSCompletions 模块的所有信息
New-Variable -Name PSCompletions -Value @{} -Option Constant

# 模块版本
$PSCompletions.version = '4.0.1'
$PSCompletions.path = @{}
$PSCompletions.path.root = Split-Path $PSScriptRoot -Parent
$PSCompletions.path.completions = Join-Path $PSCompletions.path.root 'completions'
$PSCompletions.path.core = Join-Path $PSCompletions.path.root 'core'
$PSCompletions.path.completions_json = Join-Path $PSCompletions.path.root 'completions.json'
$PSCompletions.path.config = Join-Path $PSCompletions.path.root 'config.json'
$PSCompletions.path.update = Join-Path $PSCompletions.path.core 'update.txt'
$PSCompletions.path.change = Join-Path $PSCompletions.path.core 'change.txt'

$PSCompletions.menu = @{
    const = @{
        color_item  = @(
            "item_text",
            "item_back",
            "selected_text",
            "selected_back",
            "filter_text",
            "filter_back",
            "border_text",
            "border_back",
            "status_text",
            "status_back",
            "tip_text",
            "tip_back"
        )
        color_value = @(
            'White', 'Black',
            'Gray', 'DarkGray'
            'Red', 'DarkRed',
            'Green', 'DarkGreen',
            'Blue', 'DarkBlue',
            'Cyan', 'DarkCyan',
            'Yellow', 'DarkYellow',
            'Magenta', 'DarkMagenta'
        )
        config_item = @(
            "menu_enable",
            "menu_show_tip",
            "menu_list_follow_cursor",
            "menu_tip_follow_cursor",
            "menu_is_prefix_match",
            "enter_when_single",
            "menu_selection_with_margin",
            "menu_completions_sort"
            "menu_above_margin_bottom",
            "menu_tip_cover_buffer",
            "menu_list_cover_buffer",
            "menu_above_list_max_count",
            "menu_below_list_max_count",
            "menu_between_item_and_symbol",
            "menu_list_min_width",
            "menu_list_margin_left",
            "menu_list_margin_right",
            "menu_status_symbol",
            "menu_filter_symbol"
        )
        line_item   = @(
            "horizontal",
            "vertical",
            "top_left",
            "bottom_left",
            "top_right",
            "bottom_right"
        )
    }
}

$PSCompletions.default = @{}

$PSCompletions.order = [ordered]@{}

$PSCompletions.language = $PSUICulture

$PSCompletions.wc = New-Object System.Net.WebClient

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler 'Tab' MenuComplete
}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_file {
    param( [string]$path )
    if (!(Test-Path $path)) { New-Item -ItemType File $path > $null }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_dir {
    param( [string]$path )
    if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
}

if (!(Test-Path $PSCompletions.path.config) -and !(Test-Path $PSCompletions.path.completions)) {
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod move_old_version {
        $version = (Get-ChildItem (Split-Path $this.path.root -Parent)).Name | Sort-Object { [Version]$_ } -ErrorAction SilentlyContinue
            if ($version -is [array]) {
                $old_version = $version[-2]
                if($old_version -ge "4"){
                    $old_version_dir = Join-Path (Split-Path $this.path.root -Parent) $old_version
                    $this.ensure_dir($this.path.completions)
                    Get-ChildItem "$($old_version_dir)/completions" -ErrorAction SilentlyContinue | Where-Object {
                        $_.BaseName -ne 'psc'
                    } | ForEach-Object {
                        Move-Item $_.FullName $this.path.completions -Force -ErrorAction SilentlyContinue
                    }
                    Move-Item "$($old_version_dir)/config.json" $this.path.config -Force -ErrorAction SilentlyContinue
                }
            }
    }
    $PSCompletions.move_old_version()
}

if ($PSEdition -eq "Core") {
    # pwsh (Unix)
    if ($PSVersionTable.Platform -eq 'Unix') {
        . $PSScriptRoot\pwsh\Unix\completion.ps1
        . $PSScriptRoot\pwsh\Unix\config.ps1
        . $PSScriptRoot\pwsh\Unix\menu.ps1
    }
    else {
        # pwsh (Windows)
        . $PSScriptRoot\pwsh\Win\completion.ps1
        . $PSScriptRoot\pwsh\Win\config.ps1
        . $PSScriptRoot\pwsh\Win\menu.ps1
    }
}
else {
    # powershell 5.x
    . $PSScriptRoot\powershell\completion.ps1
    . $PSScriptRoot\powershell\config.ps1
    . $PSScriptRoot\powershell\menu.ps1
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_length {
    param([string]$c)
    return $Host.UI.RawUI.NewBufferCellArray($c, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor).LongLength
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod join_path {
    $res = $args[0]
    for ($i = 1; $i -lt $args.Count; $i++) {
        $res = Join-Path $res $args[$i]
    }
    return $res
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_language {
    param ([string]$completion)
    $path_config = "$($this.path.completions)/$($completion)/config.json"
    if (!(Test-Path $path_config) -or !$this.get_raw_content($path_config)) {
        $this.download_file("$($this.url)/completions/$($completion)/config.json", $path_config)
    }
    $content_config = $this.get_raw_content($path_config) | ConvertFrom-Json
    if ($this.config.comp_config.$completion -and $this.config.comp_config.$completion.language) {
        $config_language = $this.config.comp_config.$completion.language
    }
    else {
        $config_language = $null
    }
    if ($config_language) {
        $language = if ($config_language -in $content_config.language) { $config_language }else { $content_config.language[0] }
    }
    else {
        $language = if ($this.language -in $content_config.language) { $this.language }else { $content_config.language[0] }
    }
    return $language
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_content {
    param ([string]$path)
    $res = Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' }
    if ($res) { return $res }
    return New-Object System.Collections.ArrayList
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_raw_content {
    param ([string]$path, [bool]$trim = $true)
    $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    if ($res) {
        if ($trim) { return $res.Trim() }
        return $res
    }
    return ''
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod replace_content {
    param ($data, $separator = '')
    $data = ($data -join $separator)
    $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
    $matches = [regex]::Matches($data, $pattern)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
    }
    if ($data -match $pattern) { $this.replace_content($data) }else { return $data }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod write_with_color {
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
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod show_with_less {
    param (
        $str_list,
        [string]$color = 'Green',
        [int]$show_line = [System.Console]::WindowHeight - 5
    )
    if ($str_list -is [string]) {
        $str_list = $str_list -split "`n"
    }
    $i = 0
    $need_less = [System.Console]::WindowHeight -lt ($str_list.Count + 2)
    if ($need_less) {
        $lines = $str_list.Count - $show_line
        $this.write_with_color($this.replace_content($this.info.less_tip))
        while ($i -lt $str_list.Count -and $i -lt $show_line) {
            Write-Host $str_list[$i] -f $color
            $i++
        }
        while ($i -lt $str_list.Count) {
            $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
            if ($keyCode -ne 13) {
                break
            }
            Write-Host $str_list[$i] -f $color
            $i++
        }
        $end = if ($i -lt $str_list.Count) { $false }else { $true }
        if ($end) {
            Write-Host ' '
            Write-Host '(End)' -f Black -b White -NoNewline
            while ($end) {
                $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
                if ($keyCode -ne 13) {
                    Write-Host ' '
                    break
                }
            }
        }
    }
    else {
        $str_list | ForEach-Object { Write-Host $_ -f $color }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod show_with_less_table {
    param (
        [array]$str_list,
        [array]$header = @('key', 'value', 5),
        [scriptblock]$do = {},
        [int]$show_line = [System.Console]::WindowHeight - 5
    )
    $str_list = @(
        @{
            content = "`n{0,-$($header[2] + 3)} {1}" -f $header[0], $header[1]
            color   = 'Cyan'
        },
        @{
            content = "{0,-$($header[2] + 3)} {1}" -f ('-' * $header[0].Length), ('-' * $header[1].Length)
            color   = 'Cyan'
        }
    ) + $str_list
    $i = 0
    $need_less = [System.Console]::WindowHeight -lt ($str_list.Count + 2)
    if ($need_less) {
        $lines = $str_list.Count - $show_line
        $this.write_with_color($this.replace_content($this.info.less_tip))
        & $do
        while ($i -lt $str_list.Count -and $i -lt $show_line) {
            if ($str_list[$i].bgColor) {
                Write-Host $str_list[$i].content -f $str_list[$i].color -b $str_list[$i].bgColor
            }
            else {
                Write-Host $str_list[$i].content -f $str_list[$i].color
            }
            $i++
        }
        while ($i -lt $str_list.Count) {
            $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
            if ($keyCode -ne 13) {
                break
            }
            if ($str_list[$i].bgColor) {
                Write-Host $str_list[$i].content -f $str_list[$i].color -b $str_list[$i].bgColor
            }
            else { Write-Host $str_list[$i].content -f $str_list[$i].color }
            $i++
        }
        $end = if ($i -lt $str_list.Count) { $false }else { $true }
        if ($end) {
            Write-Host ' '
            Write-Host '(End)' -f Black -b White -NoNewline
            while ($end) {
                $keyCode = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
                if ($keyCode -ne 13) {
                    Write-Host ' '
                    break
                }
            }
        }
    }
    else {
        & $do
        $str_list | ForEach-Object {
            if ($_.bgColor) {
                Write-Host $_.content -f $_.color -b $_.bgColor[2]
            }
            else {
                Write-Host $_.content -f $_.color
            }
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod confirm_do {
    param ([string]$tip, [scriptblock]$confirm_event, [bool]$write_empty_line = $true)
    $this.write_with_color($this.replace_content($tip))
    $choice = $host.UI.RawUI.ReadKey('NoEcho, IncludeKeyDown')
    if ($write_empty_line) { Write-Host '' }
    if ($choice.Character -eq 13) {
        & $confirm_event
        return $true
    }
    else {
        $this.write_with_color($this.replace_content($this.info.confirm_cancel))
        return $false
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_list {
    if (!(Test-Path $this.path.completions_json)) {
        @{ list = @('psc') } | ConvertTo-Json | Out-File $this.path.completions_json -Encoding utf8 -Force
    }
    $current_list = ($this.get_raw_content($this.path.completions_json) | ConvertFrom-Json).list
    if ($this.url) {
        try {
            $content = (Invoke-WebRequest -Uri "$($this.url)/completions.json").Content | ConvertFrom-Json

            $remote_list = $content.list

            $diff = Compare-Object $remote_list $current_list -PassThru
            if ($diff) {
                $diff | Out-File $this.path.change -Force -Encoding utf8
                $content | ConvertTo-Json | Out-File $this.path.completions_json -Encoding utf8 -Force
                $this.list = $remote_list
            }
            else {
                Clear-Content $this.path.change -Force
                $this.list = $current_list
            }
            return $remote_list
        }
        catch {
            $this.list = $current_list
            return $false
        }
    }
    $this.list = $current_list
    $this.write_with_color($this.replace_content($this.info.err.url))
    return $false
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_file {
    param(
        [string]$url,
        [string]$file
    )
    try {
        $this.wc.DownloadFile($url, $file)
    }
    catch {
        if ($this.info) {
            $download_info = @{
                url  = $url
                file = $file
            }
            $this.write_with_color($this.replace_content($this.info.err.download_file))
        }
        else {
            Write-Host "File ($(Split-Path $url -Leaf)) download failed, please check your network connection or try again later." -ForegroundColor Red
            Write-Host "File download Url: $($url)" -ForegroundColor Red
            Write-Host "File save path: $($file)" -ForegroundColor Red
            Write-Host "If you are sure that it is not a network problem, please submit an issue`n" -ForegroundColor Red
        }
        throw
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod add_completion {
    param (
        [string]$completion,
        [bool]$log = $true,
        [bool]$is_update = $false
    )
    $url = "$($this.url)/completions/$($completion)"

    $completion_dir = Join-Path $this.path.completions $completion

    $this.ensure_dir($this.path.completions)
    $this.ensure_dir($completion_dir)
    $this.ensure_dir((Join-Path $completion_dir 'language'))

    $download_info = @{
        url  = "$($url)/config.json"
        file = Join-Path $completion_dir 'config.json'
    }
    $PSCompletions.download_file($download_info.url, $download_info.file)

    $config = $this.get_content("$($completion_dir)/config.json") | ConvertFrom-Json

    $files = @(
        @{
            Uri     = "$($url)/guid.txt"
            OutFile = Join-Path $completion_dir 'guid.txt'
        }
    )

    $config.language | ForEach-Object {
        $files += @{
            Uri     = "$($url)/language/$($_).json"
            OutFile = $PSCompletions.join_path($completion_dir, 'language', "$($_).json")
        }
    }
    if ($config.hooks) {
        $files += @{
            Uri     = "$($url)/hooks.ps1"
            OutFile = Join-Path $completion_dir 'hooks.ps1'
        }
    }

    foreach ($file in $files) {
        $download_info = @{
            url  = $file.Uri
            file = $file.OutFile
        }
        try {
            $this.wc.DownloadFile($download_info.url, $download_info.file)
        }
        catch {
            $this.write_with_color($this.replace_content($this.info.err.download_file))
            Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue
            throw
        }
    }

    # 显示下载信息
    $download = if ($is_update) { $this.info.update.doing }else { $this.info.add.doing }
    $this.write_with_color("`n" + $this.replace_content($download))

    $done = if ($is_update) { $this.info.update.done }else { $this.info.add.done }

    $path_alias = Join-Path $completion_dir 'alias.txt'
    if (!(Test-Path $path_alias) -or !$this.get_raw_content($path_alias)) {
        $completion | Out-File $path_alias -encoding utf8 -Force
    }
    $language = $PSCompletions.get_language($completion)
    $json = $this.get_raw_content("$($completion_dir)/language/$($language).json") | ConvertFrom-Json
    # 如果所有文件下载完成，打印完成信息
    if ($log) {
        $this.write_with_color($this.replace_content($done))
    }

    # 如果补全有单独的配置信息，写入配置文件
    if ($json.config) {
        $this.config = $this.get_config()
        if (!$this.config.comp_config.$completion) {
            $this.config.comp_config.$completion = @{}
        }
        $json.config | ForEach-Object {
            if (!($this.config.comp_config.$completion.$($_.name))) {
                $this.config.comp_config.$completion.$($_.name) = $_.value
                $need_update_config = $true
            }
        }
        if ($need_update_config) {
            $this.config | ConvertTo-Json | Out-File $this.path.config -Force -Encoding utf8
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod init_data {
    $this.cmd = [ordered]@{}
    $this.config = $this.get_config()

    if ($this.config.language) {
        $this.language = $this.config.language
    }
    else {
        $this.language = $PSUICulture
    }
    if ($this.config.github) {
        $this.github = "$($this.config.github.Replace('github.com', 'raw.githubusercontent.com'))/main"
    }
    else {
        $this.github = 'https://raw.githubusercontent.com/abgox/PSCompletions/main'
    }
    if ($this.config.gitee) {
        $this.gitee = "$($this.config.gitee)/raw/main"
    }
    else {
        $this.gitee = 'https://gitee.com/abgox/PSCompletions/raw/main'
    }
    if ($this.config.url) {
        $this.url = $this.config.url
        $this.repo = $null
    }
    else {
        function _do($i, $k) {
            if ($this.config.$i) {
                return @($this.$i, $this.config.$i)
            }
            else {
                return @($this.$k, $this.config.$k)
            }
        }
        if ($this.language -eq 'zh-CN') {
            $info = _do 'gitee' 'github'
            $this.url = $info[0]
            $this.repo = $info[1]
        }
        else {
            $this.language = 'en-US'
            $info = _do 'github' 'gitee'
            $this.url = $info[0]
            $this.repo = $info[1]
        }
    }


    $this.ensure_dir($this.path.completions)

    if (Test-Path "$($this.path.completions)/psc") {
        $language = $this.get_language('psc')
        $path_config = "$($this.path.completions)/psc/config.json"
        $content_config = $this.get_raw_content($path_config) | ConvertFrom-Json
        if ($content_config.hooks) {
            $path_hooks = "$($this.path.completions)/psc/hooks.ps1"
            if (!(Test-Path $path_hooks)) {
                $this.download_file("$($this.url)/completions/psc/hooks.ps1", $path_hooks)
            }
        }
        $path_language = "$($this.path.completions)/psc/language/$($language).json"
        if (!(Test-Path $path_language)) {
            $this.download_file("$($this.url)/completions/psc/language/$($language).json", $path_language)
        }
        $this.info = ($this.get_raw_content($path_language) | ConvertFrom-Json).info
    }
    else {
        New-Item -ItemType Directory "$($this.path.completions)/psc" > $null
        New-Item -ItemType Directory "$($this.path.completions)/psc/language" > $null
        $language = $this.get_language('psc')
        $path_language = "$($this.path.completions)/psc/language/$($language).json"

        $this.download_file("$($this.url)/completions/psc/language/$($language).json", $path_language)
        $this.info = ($this.get_raw_content($path_language) | ConvertFrom-Json).info
        $this.add_completion('psc')
        $this.is_first_init = $true
    }

    if (!(Test-Path $PSCompletions.path.completions_json) -and !($this.download_list())) {
        $this.write_with_color($this.replace_content($this.info.err.download_list))
        throw $this.replace_content($this.info.err.download_list) -replace '<\@\w+>', ''
    }

    $this.list = ($this.get_raw_content($this.path.completions_json) | ConvertFrom-Json).list

    # update.txt 文件
    $this.ensure_file($this.path.update)
    $this.update = $this.get_content($this.path.update)

    Get-ChildItem -Path $this.path.completions -Directory | Sort-Object CreationTime | ForEach-Object {
        if (Test-Path "$($_.FullName)/config.json") {
            $this.cmd.$($_.Name) = $_.Name
        }
        else {
            Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    Get-ChildItem -Path $this.path.completions | ForEach-Object {
        $path_alias = Join-Path $_.FullName 'alias.txt'
        $this.cmd.$($_.Name) = @()
        if (Test-Path $path_alias) {
            $alias_list = $this.get_content($path_alias)
            if ($alias_list) {
                foreach ($alias in $alias_list) { $this.cmd.$($_.Name) += $alias.Trim() }
            }
            else {
                $this.cmd.$($_.Name) += $_.Name
                $_.Name | Out-File $path_alias -Encoding utf8 -Force
            }
        }
        else {
            $this.cmd.$($_.Name) += $_.Name
            $_.Name | Out-File $path_alias -Encoding utf8 -Force
        }
    }

    $this.alias = @{}
    $this.cmd.Keys | ForEach-Object {
        foreach ($alias in $this.cmd.$_) { $this.alias.$($alias) = $_ }
    }

    $this.cmd.keys | ForEach-Object {
        $this.handle_completion($_)
        if ((!$this.config.comp_config.$_)) {
            $this.config.comp_config.$_ = @{}
        }
    }
}

$PSCompletions.init_data()

if ($PSCompletions.is_first_init) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.init_info))
}

$PSCompletions.cmd.keys | Where-Object { $_ -ne 'psc' } | ForEach-Object {
    <#
        这里使用 PowerShell 的内置变量 $args 作为临时变量
        虽然 $args 不是一个有意义的变量名，但是它的特性很适合作为一个不污染全局的临时变量
        使用 $args 作为临时变量，不会影响它在函数以及脚本中接受传递参数的作用
    #>
    foreach ($args in $PSCompletions.cmd.$_) {
        if ($args -ne $_) { Set-Alias $args $_ }
    }
}

$PSCompletions.cmd.psc | ForEach-Object {
    if ($_ -ne 'PSCompletions') { Set-Alias $_ PSCompletions }
}

if ($PSCompletions.config.module_update -match '^\d+(\.\d+)+$') {
    if ($PSCompletions.config.module_update -eq $PSCompletions.version) {
        $PSCompletions.set_config('module_update', 1)
    }
    else {
        $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/module/log.json", (Join-Path $PSCompletions.path.core 'log.json'))
        $null = $PSCompletions.confirm_do($PSCompletions.info.module.update, {
                if ($PSEdition -eq "Desktop") {
                    # powershell 5.1
                    $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module_updating))
                    try {
                        Update-Module PSCompletions -ErrorAction Stop
                    }
                    catch {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update_err))
                    }
                    if ($PSCompletions.config.module_update -in (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent)).BaseName) {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update_done))
                    }
                    else {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update_err))
                    }
                }
                else {
                    # pwsh
                    $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module_updating))
                    try {
                        Update-Module PSCompletions -ErrorAction Stop
                    }
                    catch {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update_err))
                    }
                    if ($PSCompletions.config.module_update -in (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent)).BaseName) {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update_done))
                    }
                    else {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.update_err))
                    }
                }
            })
    }
}
else {
    if ($PSCompletions.config.update -eq 1) {
        if ($PSCompletions.update -or $PSCompletions.get_content($PSCompletions.path.change)) {
            $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.update_info))
        }
    }
}

# 缓存 completion 数据并后台检测更新
$PSCompletions.job = Start-Job -ScriptBlock {
    param($PSCompletions, $root)
    function ConvertFrom-JsonToHashtable([string]$json) {
        <#
            # 处理 json 文件中的一些特殊情况
            # -  如果有键名为空的情况，则替换为随机的 guid
            # -  并移除最后一个属性的 ,
        #>
        $matches = [regex]::Matches($json, '\s*"\s*"\s*:')
        foreach ($match in $matches) {
            $json = $json -replace $match.Value, "`"empty_key_$([System.Guid]::NewGuid().Guid)`":"
        }
        $json = [regex]::Replace($json, ",`n?(\s*`n)?\}", "}")
        function ConvertToHashtable($obj) {
            $hash = @{}
            if ($obj -is [System.Management.Automation.PSCustomObject]) {
                $obj | Get-Member -MemberType Properties | ForEach-Object {
                    $k = $_.Name # Key
                    $v = $obj.$k # Value
                    if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
                        # Handle array
                        $arr = @()
                        foreach ($item in $v) {
                            $arr += if ($item -is [System.Management.Automation.PSCustomObject]) { ConvertToHashtable($item) }else { $item }
                        }
                        $hash[$k] = $arr
                    }
                    elseif ($v -is [System.Management.Automation.PSCustomObject]) {
                        # Handle object
                        $hash[$k] = ConvertToHashtable($v)
                    }
                    else { $hash[$k] = $v }
                }
            }
            else { $hash = $obj }
            $hash
        }
        # Recurse
        ConvertToHashtable ($json | ConvertFrom-Json)
    }

    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_raw_content {
        param ([string]$path, [bool]$trim = $true)
        $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        if ($res) {
            if ($trim) { return $res.Trim() }
            return $res
        }
        return ''
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_language {
        param ([string]$completion)
        $path_config = "$($this.path.completions)/$($completion)/config.json"
        if (!(Test-Path $path_config) -or !$this.get_raw_content($path_config)) {
            $this.download_file("$($this.url)/completions/$($completion)/config.json", $path_config)
        }
        $content_config = $this.get_raw_content($path_config) | ConvertFrom-Json
        if ($this.config.comp_config.$completion -and $this.config.comp_config.$completion.language) {
            $config_language = $this.config.comp_config.$completion.language
        }
        else {
            $config_language = $null
        }
        if ($config_language) {
            $language = if ($config_language -in $content_config.language) { $config_language }else { $content_config.language[0] }
        }
        else {
            $language = if ($this.language -in $content_config.language) { $this.language }else { $content_config.language[0] }
        }
        return $language
    }

    $completion_datas = @{}
    $PSCompletions.cmd.Keys | ForEach-Object {
        $language = $PSCompletions.get_language($_)
        $path_language = "$($PSCompletions.path.completions)/$($_)/language/$($language).json"
        if (Test-Path $path_language) {
            $completion_datas.$_ = ConvertFrom-JsonToHashtable $PSCompletions.get_raw_content($path_language)
        }
        else {
            try {
                $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/completions/$($_)/language/$($language).json", $path_language)
                $completion_datas.$_ = ConvertFrom-JsonToHashtable $PSCompletions.get_raw_content($path_language)
            }
            catch {
                Remove-Item "$($PSCompletions.path.completions)/$($_)" -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_config {
        if (Test-Path $this.path.config) {
            $c = ConvertFrom-JsonToHashtable $this.get_raw_content($this.path.config)
            if ($c) {
                @('env', 'symbol', 'menu_line', 'menu_color', 'menu_config') | ForEach-Object {
                    foreach ($config in $this.default.$_.Keys) {
                        # 如果配置不存在，则添加默认配置
                        if ($config -notin $c.keys) {
                            $hasDiff = $true
                            $c.$config = $this.default.$_.$config
                        }
                    }
                }
                if (!$c.comp_config) {
                    $hasDiff = $true
                    $c.comp_config = @{}
                }
                if ($hasDiff) {
                    $c | ConvertTo-Json | Out-File $this.path.config -Encoding utf8 -Force
                }
                return $c
            }
            else {
                $need_init = $true
            }
        }
        else {
            $need_init = $true
        }
        if ($need_init) {
            $c = @{}
            @('env', 'symbol', 'menu_line', 'menu_color', 'menu_config') | ForEach-Object {
                foreach ($config in $this.default.$_.Keys) {
                    $c.$config = $this.default.$_.$config
                }
            }
            $c.comp_config = @{}
            $c | ConvertTo-Json | Out-File $this.path.config -Encoding utf8 -Force
        }
        return $c
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod set_config {
        param ([string]$k, $v)
        $c = $this.get_config()
        $c.$k = $v
        $this.config = $c
        $c | ConvertTo-Json | Out-File $this.path.config -Encoding utf8
    }
    # download list
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_list {
        if (!(Test-Path $this.path.completions_json)) {
            @{ list = @('psc') } | ConvertTo-Json | Out-File $this.path.completions_json -Encoding utf8 -Force
        }
        $current_list = ($this.get_raw_content($this.path.completions_json) | ConvertFrom-Json).list
        if ($this.url) {
            try {
                $content = (Invoke-WebRequest -Uri "$($this.url)/completions.json").Content | ConvertFrom-Json

                $remote_list = $content.list

                $diff = Compare-Object $remote_list $current_list -PassThru
                if ($diff) {
                    $diff | Out-File $this.path.change -Force -Encoding utf8
                    $content | ConvertTo-Json | Out-File $this.path.completions_json -Encoding utf8 -Force
                }
                else {
                    Clear-Content $this.path.change -Force
                }
            }
            catch {}
        }
    }

    $PSCompletions.download_list()

    # check version
    try {
        if ($PSCompletions.config.module_update -eq 1) {
            $response = Invoke-WebRequest -Uri "$($PSCompletions.url)/module/version.txt"
            $content = $response.Content.Trim()
            $versions = @($PSCompletions.version, $content) | Sort-Object { [Version] $_ }
            if ($versions[-1] -ne $PSCompletions.version) {
                $PSCompletions.set_config('module_update', $versions[-1])
            }
        }
    }
    catch {}

    # check update
    if ($PSCompletions.config.update -eq 1) {
        $update_list = [System.Collections.Generic.List[string]]@()
        Get-ChildItem $PSCompletions.path.completions | Where-Object { $_.Name -in $PSCompletions.list } | ForEach-Object {
            try {
                $response = Invoke-WebRequest -Uri "$($PSCompletions.url)/completions/$($_.Name)/guid.txt"
                $content = $response.Content.Trim()
                $guid = $PScompletions.get_raw_content("$($PSCompletions.path.completions)/$($_.Name)/guid.txt")
                if ($guid -ne $content) { $update_list.Add($_.Name) }
            }
            catch {}
        }
        if ($update_list) { $update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8 }
        else { Clear-Content $PSCompletions.path.update -Force }
    }
    return $completion_datas
} -ArgumentList $PSCompletions
