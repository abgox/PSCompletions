using namespace System.Management.Automation
# 创建一个常量对象，用于存储 PSCompletions 模块的所有信息
New-Variable -Name PSCompletions -Value @{} -Option ReadOnly

# 模块版本
$PSCompletions.version = '4.2.8'
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
            "menu_filter_symbol",
            "menu_trigger_key",
            "menu_enhance"
            "menu_show_tip_when_enhance"
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

$PSCompletions.encoding = [console]::OutputEncoding

$PSCompletions.wc = New-Object System.Net.WebClient

if (!(Test-Path $PSCompletions.path.config) -and !(Test-Path $PSCompletions.path.completions)) {
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod move_old_version {
        $version = (Get-ChildItem (Split-Path $this.path.root -Parent) -ErrorAction SilentlyContinue).Name | Sort-Object { [Version]$_ } -ErrorAction SilentlyContinue
        if ($version -is [array]) {
            $old_version = $version[-2]
            if ($old_version -match "^\d+\.\d.*" -and $old_version -ge "4") {
                $old_version_dir = Join-Path (Split-Path $this.path.root -Parent) $old_version
                if (!(Test-Path $this.path.completions)) { New-Item -ItemType Directory $this.path.completions > $null }
                foreach ($_ in Get-ChildItem "$($old_version_dir)/completions" -ErrorAction SilentlyContinue) {
                    Move-Item $_.FullName $this.path.completions -Force -ErrorAction SilentlyContinue
                }
                Move-Item "$($old_version_dir)/config.json" $this.path.config -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $PSCompletions.move_old_version()
}

. $PSScriptRoot\config.ps1

if ($PSEdition -eq "Core" -and !$IsWindows) {
    # WSL/Unix...
    . $PSScriptRoot\utils\Core.ps1
    . $PSScriptRoot\completion\unix.ps1
}
else {
    # Windows...
    . $PSScriptRoot\utils\$PSEdition.ps1
    . $PSScriptRoot\completion\win.ps1
    . $PSScriptRoot\menu\win.ps1
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod split_array {
    <#
    .Synopsis
        分割数组
    .Description
        三个参数:
        $array: 数组
        $count: 每个数组的元素个数
        $by_count: 如果此值为 $true, 则 $count 为指定的数组个数，否则为每个数组的元素个数
    #>
    param ([array]$array, [int]$count, [bool]$by_count)
    if ($by_count) {
        $ChunkSize = [math]::Ceiling($array.Length / $count)
    }
    else {
        $ChunkSize = $count
    }
    $chunks = @()
    for ($i = 0; $i -lt $array.Length; $i += $ChunkSize) {
        $chunks += , ($array[$i..([math]::Min($i + $ChunkSize - 1, $array.Length - 1))])
    }
    $chunks
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_file {
    param([string]$path)
    if (!(Test-Path $path)) { New-Item -ItemType File $path > $null }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_dir {
    param([string]$path)
    if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod join_path {
    $res = $args[0]
    for ($i = 1; $i -lt $args.Count; $i++) {
        $res = Join-Path $res $args[$i]
    }
    $res
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
    $language
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_content {
    param ([string]$path)
    $res = Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' }
    if ($res) { return $res }
    New-Object System.Collections.ArrayList
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_raw_content {
    param ([string]$path, [bool]$trim = $true)
    $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    if ($res) {
        if ($trim) { return $res.Trim() }
        return $res
    }
    ''
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod replace_content {
    param ($data, $separator = '')
    $data = $data -join $separator
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
    $str_list = foreach ($_ in $str -split '(<\@[^>]+>.*?(?=<\@|$))' | Where-Object { $_ -ne '' }) {
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
        [int]$show_line = [System.Console]::WindowHeight - 7
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
        foreach ($_ in $str_list) { Write-Host $_ -f $color }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod show_with_less_table {
    param (
        [array]$str_list,
        [array]$header = @('key', 'value', 5),
        [scriptblock]$do = {},
        [int]$show_line = [System.Console]::WindowHeight - 7
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
        foreach ($_ in $str_list) {
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
        @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $this.path.completions_json -Encoding utf8 -Force
    }
    $current_list = ($this.get_raw_content($this.path.completions_json) | ConvertFrom-Json).list
    if ($this.url) {
        try {
            $content = (Invoke-WebRequest -Uri "$($this.url)/completions.json").Content | ConvertFrom-Json

            $remote_list = $content.list

            $diff = Compare-Object $remote_list $current_list -PassThru
            if ($diff) {
                $diff | Out-File $this.path.change -Force -Encoding utf8
                $content | ConvertTo-Json -Depth 100 -Compress | Out-File $this.path.completions_json -Encoding utf8 -Force
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
    $false
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
        [bool]$log = $true
    )
    $url = "$($this.url)/completions/$($completion)"

    $is_update = Test-Path "$($this.path.completions)/$($completion)"

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
    foreach ($_ in $config.language) {
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
        $alias = if ($config.alias) { $config.alias -join "`n" }else { $completion }
        $alias | Out-File $path_alias -encoding utf8 -Force
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
        foreach ($_ in $json.config) {
            if (!($this.config.comp_config.$completion.$($_.name))) {
                $this.config.comp_config.$completion.$($_.name) = $_.value
                $need_update_config = $true
            }
        }
        if ($need_update_config) {
            $this.config | ConvertTo-Json -Depth 100 -Compress | Out-File $this.path.config -Force -Encoding utf8
        }
    }
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod init_data {
    $this.data = [ordered]@{}
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
        function _do {
            param($i, $k)
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
        $this.ensure_dir("$($this.path.completions)/psc")
        $this.ensure_dir("$($this.path.completions)/psc/language")
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

    $completions_dir_list = Get-ChildItem -Path $this.path.completions -Directory -ErrorAction SilentlyContinu
    if ($completions_dir_list.Count -ge 10) {
        # 使用线程安全的数据结构，避免出现多线程同时访问同一个数据结构,导致数据损坏
        $PSCompletions.cmd = [System.Collections.Concurrent.ConcurrentDictionary[[string], [System.Collections.Generic.List[System.String]]]]::new()
        $PSCompletions.alias = [System.Collections.Concurrent.ConcurrentDictionary[[string], [System.Collections.Generic.List[System.String]]]]::new()

        $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
        $runspacePool.Open()
        $runspaces = @()
        foreach ($arr in $PSCompletions.split_array($completions_dir_list, [Environment]::ProcessorCount, $true)) {
            $runspace = [powershell]::Create().AddScript({
                    param($paths, $this)
                    function get_content {
                        param ([string]$path)
                        $res = Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' }
                        if ($res) { return $res }
                        New-Object System.Collections.ArrayList
                    }
                    foreach ($path in $paths) {
                        $name = $path.Name
                        if ((!$this.config.comp_config.$name)) {
                            $this.config.comp_config.$name = @{}
                        }
                        $path_alias = Join-Path $path 'alias.txt'
                        $this.cmd.$name = @()
                        if (Test-Path $path_alias) {
                            $alias_list = get_content $path_alias
                            if ($alias_list) {
                                foreach ($alias in $alias_list) {
                                    $alias = $alias.Trim()
                                    if ($alias) {
                                        $this.alias.$alias = $name
                                        $this.cmd.$name += $alias
                                    }
                                }
                            }
                            else {
                                $this.alias.$name = $name
                                $this.cmd.$name += $name
                                $name | Out-File $path_alias -Encoding utf8 -Force
                            }
                        }
                        else {
                            $this.alias.$name = $name
                            $this.cmd.$name += $name
                            $name | Out-File $path_alias -Encoding utf8 -Force
                        }
                    }
                }).AddArgument($arr).AddArgument($this)

            $runspace.RunspacePool = $runspacePool
            $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
        }

        # 等待所有任务完成
        foreach ($rs in $runspaces) {
            $rs.Runspace.EndInvoke($rs.Job)
            $rs.Runspace.Dispose()
        }

        $runspacePool.Close()
        $runspacePool.Dispose()
    }
    else {
        $PSCompletions.cmd = @{}
        $PSCompletions.alias = @{}
        foreach ($_ in Get-ChildItem -Path $this.path.completions -Directory -ErrorAction SilentlyContinue) {
            $path_alias = Join-Path $_.FullName 'alias.txt'
            $name = $_.Name
            if ((!$this.config.comp_config.$name)) {
                $this.config.comp_config.$name = @{}
            }
            $this.cmd.$name = @()
            if (Test-Path $path_alias) {
                $alias_list = $this.get_content($path_alias)
                if ($alias_list) {
                    foreach ($alias in $alias_list) {
                        $alias = $alias.Trim()
                        if ($alias) {
                            $this.cmd.$name += $alias
                            $this.alias.$alias = $name
                        }
                    }
                }
                else {
                    $this.alias.$name = $name
                    $this.cmd.$name += $name
                    $name | Out-File $path_alias -Encoding utf8 -Force
                }
            }
            else {
                $this.alias.$name = $name
                $this.cmd.$name += $name
                $name | Out-File $path_alias -Encoding utf8 -Force
            }
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_length {
    param([string]$str)
    $Host.UI.RawUI.NewBufferCellArray($str, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor).LongLength
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_powershell_menu {
    param($filter_list)
    if ($Host.UI.RawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        ''
        return
    }

    # is_show_tip
    if ($PSCompletions.current_cmd) {
        $json = $PSCompletions.data.$($PSCompletions.current_cmd)
        $info = $json.info

        $menu_show_tip = $PSCompletions.config.comp_config.$($PSCompletions.current_cmd).menu_show_tip
        if ($menu_show_tip -ne $null) {
            $this.is_show_tip = $menu_show_tip -eq 1
        }
        else {
            $this.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
        }
    }
    else {
        $this.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
    }

    if ($this.is_show_tip) {
        foreach ($_ in $filter_list) {
            if ($_.ToolTip) {
                $tip = $PSCompletions.replace_content($_.ToolTip)
                $tip_arr = $tip -split "`n"
            }
            else {
                $tip = ' '
                $tip_arr = @()
            }
            $this.tip_max_height = [Math]::Max($this.tip_max_height, $tip_arr.Count)
            [CompletionResult]::new($_.CompletionText, $_.ListItemText, 'ParameterValue', $tip)
        }
    }
    else {
        foreach ($_ in $filter_list) {
            [CompletionResult]::new($_.CompletionText, $_.ListItemText, 'ParameterValue', ' ')
        }
    }
    $PSCompletions.current_cmd = $null
}

$PSCompletions.init_data()

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler $PSCompletions.config.menu_trigger_key MenuComplete
    $PSCompletions.generate_completion()
    $PSCompletions.handle_completion()
}

if ($PSCompletions.is_first_init) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.init_info))
}

foreach ($_ in $PSCompletions.cmd.keys | Where-Object { $_ -ne 'psc' }) {
    <#
        这里使用 PowerShell 的内置变量 $args 作为临时变量
        虽然 $args 不是一个有意义的变量名，但是它的特性很适合作为一个不污染全局的临时变量
        使用 $args 作为临时变量，不会影响它在函数以及脚本中接受传递参数的作用
    #>
    foreach ($args in $PSCompletions.cmd.$_) {
        if ($args -ne $_) { Set-Alias $args $_ -ErrorAction SilentlyContinue }
    }
}

foreach ($_ in $PSCompletions.cmd.psc) {
    if ($_ -ne $PSCompletions.config.function_name) { Set-Alias $_ $PSCompletions.config.function_name -ErrorAction SilentlyContinue }
}

if ($PSCompletions.config.module_update -match "^\d+\.\d.*") {
    if ($PSCompletions.config.module_update -gt $PSCompletions.version) {
        $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/module/log.json", (Join-Path $PSCompletions.path.core 'log.json'))
        $null = $PSCompletions.confirm_do($PSCompletions.info.module.update, {
                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.module.updating))
                Update-Module PSCompletions -Force -ErrorAction Stop
            })
    }
    else {
        $PSCompletions.set_config('module_update', 1)
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
$PSCompletions.start_job()
