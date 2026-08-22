Microsoft.PowerShell.Core\Set-StrictMode -Off

if ($PSCompletions.guid) { return }

$_ = "$PSScriptRoot/data"
New-Variable -Name PSCompletions -Option Constant -Value @{
    version     = '7.2.0'
    binary_ok   = $false
    initialized = $false
    path        = @{
        root             = $PSScriptRoot
        completions      = "$_/completions"
        data             = "$_/settings.json"
        temp             = "$_/temp"
        menu             = "$_/temp/menu"
        cache            = "$_/temp/cache"
        log              = "$_/temp/log"
        order            = "$_/temp/order"
        completions_json = "$_/temp/completions.json"
        change           = "$_/temp/change.json"
    }
    cmd         = ''
    guid        = '00929632-527d-4dab-a5b3-21197faccd05'
    language    = $PSUICulture
    menu        = @{
        encoding                      = [System.Text.Encoding]::GetEncoding(0)
        module_completion_menu_script = {
            try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

            # Lazy init: the first Tab press performs the deferred initialization, then the menu proceeds
            if (-not $PSCompletions.initialized) {
                $PSCompletions.initialize()
                if (-not $PSCompletions.binary_ok) { return }
            }

            $buffer = ''
            $cursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursor)
            if (!$buffer) { return }

            $PSCompletions.buffer_after_cursor = $buffer.Substring($cursor)
            $buffer = $PSCompletions.buffer_before_cursor = $buffer.Substring(0, $cursor)
            if (!$buffer) { return }

            $isSpaceTab = $buffer[-1] -eq ' '
            $inputs = @()
            $matches = [regex]::Matches($buffer, $PSCompletions.input_pattern)
            foreach ($match in $matches) { $inputs += $match.Value }

            if (!$inputs) { return }

            $alias = $inputs[0]
            if ($null -eq $PSCompletions.data.aliasMap[$alias]) { $alias = $inputs[0] -replace '\.(exe|cmd|bat)$', '' }

            if ($null -ne $PSCompletions.data.aliasMap[$alias] -and ($isSpaceTab -or ($inputs.Count -gt 1 -and $inputs[-1] -notmatch '^[''"]?(?:[A-Za-z]:[/\\]|(?:\.\.?|~)?[/\\]).*'))) {
                $PSCompletions.cmd = $cmd = $PSCompletions.data.aliasMap[$alias]
                $filter_list = $PSCompletions.get_completion($cmd, $inputs)
                $result = $PSCompletions.menu.show_module_menu($filter_list)
                if ($result) {
                    # Only the word being edited is replaced: wordStart/wordEnd derive from the cursor position
                    if ($isSpaceTab) {
                        $wordStart = $buffer.Length
                    }
                    else {
                        $wordStart = $buffer.Length - [string]$inputs[-1].Length
                    }
                    # Extend the word end only when the char after the cursor continues the word (space/quote/empty = new-word boundary)
                    $afterText = [string]$PSCompletions.buffer_after_cursor
                    $wordEnd = $buffer.Length
                    if ($afterText -and $afterText[0] -ne ' ' -and $afterText[0] -ne "`t" -and $afterText[0] -ne '"' -and $afterText[0] -ne "'") {
                        $wordEnd += [regex]::Match($afterText, $PSCompletions.input_pattern).Length
                    }
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($wordStart, $wordEnd - $wordStart, $result)
                }
            }
            else {
                # Native fallback: route PowerShell's TabExpansion2 results through the module menu when enable_native_completion is set
                if (!$PSCompletions.config.enable_native_completion) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
                    return
                }
                try {
                    $completion = TabExpansion2 $buffer $cursor
                }
                catch {
                    return
                }
                $filter_list = $completion.CompletionMatches
                if (!$filter_list) { return }

                $PSCompletions.cmd = $cmd = $inputs[0]
                if (![System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($cmd)) {
                    # Hand the raw input tokens to the engine: it decides whether the first token
                    # is still being completed (`g<Tab>`, `.\src\<Tab>`) and only then consults
                    # the shared global files (_commands.json / _paths.json). Once the command is
                    # complete (`npm <Tab>`) the candidates are its own subcommands.
                    $filter_list = $PSCompletions.apply_completions_sort($cmd, $filter_list, $inputs, $PSCompletions.buffer_before_cursor[-1] -eq ' ')
                }
                $result = $PSCompletions.menu.show_module_menu($filter_list)
                if ($result) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($completion.ReplacementIndex, $completion.ReplacementLength, $result)
                }
            }
        }
    }
}

if ($IsWindows -or $PSEdition -eq 'Desktop') {
    if ($PSCompletions.path.root -like "$env:ProgramFiles*" -or $PSCompletions.path.root -like "$env:SystemRoot*") {
        if (![Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Microsoft.PowerShell.Utility\Write-Host -ForegroundColor Red @"

[PSCompletions] Administrator Required
-------------------------------------------------
PSCompletions is installed in a system-level directory.
Location: $($PSCompletions.path.root)

To use PSCompletions normally, please:
1. Run PowerShell as Administrator.
2. Or reinstall the module to a user-writable location via '-Scope CurrentUser'.

Refer to: https://pscompletions.abgox.com/docs/require-admin

"@
            return
        }
    }
}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod initialize {
    param([bool]$methodsOnly = $false)
    if ($PSCompletions.initialized) { return }

    $PSCompletions.replace_pattern = [regex]::new('(?s)\{\{(.*?(\})*)(?=\}\})\}\}', [System.Text.RegularExpressions.RegexOptions]::Compiled)
    $PSCompletions.input_pattern = [regex]::new("(?:`"[^`"]*`"|'[^']*'|\S)+", [System.Text.RegularExpressions.RegexOptions]::Compiled)

    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion -Force {
        if ([System.IO.File]::Exists($PSCompletions.path.data)) {
            $_ = Get-Content -Raw -LiteralPath $PSCompletions.path.data -Encoding utf8 | ConvertFrom-Json -ErrorAction SilentlyContinue
            $PSCompletions.psc_alias = $_.alias.PSObject.Properties['psc'].value
            $PSCompletions._key = $_.config.trigger_key
        }
        else {
            $PSCompletions.psc_alias = @('psc')
            $PSCompletions._key = 'Tab'
        }
        foreach ($_ in $PSCompletions.psc_alias) {
            Microsoft.PowerShell.Utility\Set-Alias $_ PSCompletions -Force -ErrorAction Ignore -Scope Global
        }
        Set-PSReadLineKeyHandler -Key $PSCompletions._key -ScriptBlock $PSCompletions.menu.module_completion_menu_script
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ConvertFrom_JsonAsHashtable -Force {
        param([string]$json)
        # https://github.com/abgox/ConvertFrom-JsonAsHashtable
        if ($PSVersionTable.PSVersion.Major -ge 7) { return ConvertFrom-Json $json -AsHashtable }
        # V5: optimized for completion JSON schema (strings, numbers, arrays, objects)
        $parsed = ConvertFrom-Json $json
        function ConvertObj {
            param($obj)
            if ($obj -is [System.Management.Automation.PSCustomObject]) {
                $ht = @{}
                foreach ($p in $obj.PSObject.Properties) { $ht[$p.Name] = ConvertObj $p.Value }
                return $ht
            }
            if ($obj -is [array]) {
                $list = [System.Collections.Generic.List[object]]::new($obj.Count)
                foreach ($item in $obj) { $list.Add((ConvertObj $item)) }
                return , $list.ToArray()
            }
            return $obj
        }
        ConvertObj $parsed
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_dir -Force {
        param([string]$path)
        if (![System.IO.Directory]::Exists($path)) { New-Item -ItemType Directory $path -ErrorAction SilentlyContinue | Out-Null }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_raw_content -Force {
        param ([string]$path, [bool]$trim = $true)
        try {
            $res = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
            if ($trim) { return $res.Trim() }
            return $res
        }
        catch {
            return ''
        }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_content -Force {
        param ([string]$path)
        try {
            $res = [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8).Where({ $_ -ne '' })
            if ($res) { return $res }
        }
        catch { }
        , @()
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod wrap_whitespace -Force {
        param([string]$String)
        if ([string]::IsNullOrWhiteSpace($String)) { return "`"$String`"" }
        if ($String.StartsWith(' ') -or $String.EndsWith(' ')) {
            if ($String.Contains('"')) {
                if ($String.Contains("'")) { return $String } else { return "'$String'" }
            }
            else { return "`"$String`"" }
        }
        return $String
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod replace_content -Force {
        param ($data, $separator = '')
        $data = [string]::Join($separator, @($data))
        if ($data -notlike '*{{*') { return $data }
        $matchList = [regex]::Matches($data, $PSCompletions.replace_pattern)
        foreach ($match in $matchList) {
            $expr = $match.Groups[1].Value
            $value = $null
            if ($expr -match '^\$info\.([\w.]+)$') {
                $value = $info
                foreach ($p in ($matches[1] -split '\.')) {
                    if ($null -eq $value) { break }
                    $value = $value.$p
                }
            }
            elseif ($expr -match '^\$PSCompletions\.config\.(\w+)$') {
                $value = $PSCompletions.config[$matches[1]]
            }
            elseif ($expr -match '^\$env:(\w+)$') {
                $value = [Environment]::GetEnvironmentVariable($matches[1])
            }
            if ($null -ne $value) {
                $valueStr = if ($value -is [string]) { $value } elseif ($null -eq $value) { '' } else { [string]::Join($separator, @($value)) }
                $data = $data.Replace($match.Value, $valueStr)
            }
            else {
                $data = $data.Replace($match.Value, [string]::Join($separator, @(Invoke-Expression $expr)))
            }
        }
        if ($data -match $PSCompletions.replace_pattern) { $PSCompletions.replace_content($data) }else { return $data }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_language -Force {
        param ([string]$completion)
        if ($PSCompletions.lang_cache.ContainsKey($completion)) {
            return $PSCompletions.lang_cache[$completion]
        }
        $path_config = "$($PSCompletions.path.completions)/$completion/config.json"
        $raw_config = $PSCompletions.get_raw_content($path_config)
        $content_config = $null
        if ($raw_config) {
            try { $content_config = $raw_config | ConvertFrom-Json } catch { $content_config = $null }
        }
        if (!$content_config -or !$content_config.language) {
            $PSCompletions.download_file("completions/$completion/config.json", $path_config, $PSCompletions.urls)
            $raw_retry = $PSCompletions.get_raw_content($path_config)
            if ($raw_retry) {
                try { $content_config = $raw_retry | ConvertFrom-Json } catch { $content_config = $null }
            }
            if ($content_config) {
                $content_config | ConvertTo-Json -Compress | Out-File $path_config -Encoding utf8 -Force
            }
        }
        if (-not $content_config -or -not $content_config.language) { return $PSCompletions.language }
        $config_language = $PSCompletions.config.completion[$completion].language
        if ($config_language) {
            $language = if ($config_language -in $content_config.language) { $config_language }else { $content_config.language[0] }
        }
        else {
            $language = if ($PSCompletions.language -in $content_config.language) { $PSCompletions.language }else { $content_config.language[0] }
        }
        $PSCompletions.lang_cache[$completion] = $language
        $language
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod render_library_changes -Force {
        $json = $PSCompletions.get_raw_content($PSCompletions.path.change)
        if (-not $json) { return }
        $changes = $null
        try { $changes = $PSCompletions.ConvertFrom_JsonAsHashtable($json) } catch { }
        if ($null -eq $changes) { return }
        $upd = @($changes.update)
        $add = @($changes.added)
        $rm = @($changes.removed)
        $renamed = @($changes.renamed)
        if ($upd -or $add -or $rm -or $renamed) {
            $PSCompletions.update = $upd
            $PSCompletions.added = $add
            $PSCompletions.removed = $rm
            $PSCompletions.renamed = $renamed
            $template = $PSCompletions.info.update_info
            if (-not $template) {
                # Rendered after a psc command that did not init (list/info/alias/config): fall back to disk.
                try {
                    $pscLang = $PSCompletions.get_language('psc')
                    $pscData = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/psc/language/$pscLang.json"))
                    if ($pscData.info.update_info) { $template = $pscData.info.update_info }
                }
                catch { }
            }
            $PSCompletions.write_with_color($PSCompletions.replace_content($template))
            # added/removed are one-shot (consumed on display); update/renamed/module persist.
            $changes.added = @()
            $changes.removed = @()
            try {
                [System.IO.File]::WriteAllText(
                    $PSCompletions.path.change,
                    ($changes | ConvertTo-Json -Depth 6 -Compress),
                    [System.Text.Encoding]::UTF8)
            }
            catch { }
        }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod write_with_color -Force {
        param([string]$str)
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

        $color_list = @()
        $str = $str -replace "`n", $PSCompletions.guid
        $str_list = foreach ($_ in ($str -split '(<\@[^>]+>.*?(?=<\@|$))').Where({ $_ -ne '' })) {
            if ($_ -match '<\@([\s\w]+)>(.*)') {
                ($matches[2] -replace $PSCompletions.guid, "`n") -replace '^<\@>', ''
                $color = $matches[1] -split ' '
                $color_list += @{color = $color[0]; bgColor = $color[1] }
            }
            else {
                ($_ -replace $PSCompletions.guid, "`n") -replace '^<\@>', ''
                $color_list += @{color = $null; bgColor = $null }
            }
        }
        $str_list = @($str_list)
        for ($i = 0; $i -lt $str_list.Count; $i++) {
            $param = @{ Object = $str_list[$i]; NoNewline = $true }
            if ($color_list[$i]['color']) { $param['ForegroundColor'] = $color_list[$i]['color'] }
            if ($color_list[$i]['bgColor']) { $param['BackgroundColor'] = $color_list[$i]['bgColor'] }
            Microsoft.PowerShell.Utility\Write-Host @param
        }
        Microsoft.PowerShell.Utility\Write-Host ''
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod download_file -Force {
        param([string]$path, [string]$file, [array]$baseUrl)
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

        $params = @{ ErrorAction = 'Stop' }
        if ($PSEdition -eq 'Core') { $params['OperationTimeoutSeconds'] = 30 } else { $params['TimeoutSec'] = 30 }
        for ($i = 0; $i -lt $baseUrl.Count; $i++) {
            $item = $baseUrl[$i]
            $url = $item + '/' + $path
            $params['Uri'] = $url
            $params['OutFile'] = $file
            try {
                Invoke-RestMethod @params
                break
            }
            catch {
                if ($i -eq $baseUrl.Count - 1) {
                    throw
                }
                else {
                    Write-Host $_.Exception.Message -ForegroundColor Red
                }
            }
        }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod write_binary_error -Force {
        Microsoft.PowerShell.Utility\Write-Host -ForegroundColor Red @'

[PSCompletions] Binary files not found.
Refer to: https://pscompletions.abgox.com/docs/binary-not-found

'@
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod psc_binary -Force {
        if ($null -ne $PSCompletions.psc_bin_path) { return $PSCompletions.psc_bin_path }
        $menuBin = $PSCompletions.menu.menu_binary()
        if (!$menuBin) { return }
        $dir = [System.IO.Path]::GetDirectoryName($menuBin)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($menuBin)
        $psc = [System.IO.Path]::Combine($dir, ('psc' + [System.IO.Path]::GetExtension($menuBin)))
        if (-not [System.IO.File]::Exists($psc)) { return }
        $PSCompletions.psc_bin_path = $psc
        $psc
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_menu_buffer -Force {
        param($startPos, $endPos)
        $rawUI = $Host.UI.RawUI
        $top = [System.Management.Automation.Host.Coordinates]::new($startPos.X, $startPos.Y)
        $bottom = [System.Management.Automation.Host.Coordinates]::new($endPos.X , $endPos.Y)
        $buffer = $rawUI.GetBufferContents([System.Management.Automation.Host.Rectangle]::new($top, $bottom))
        @{ top = $top; bottom = $bottom; buffer = $buffer }
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_menu_output -Force {
        param($item)
        $suffix = if ($PSCompletions.config.enable_append_space) { ' ' } else { '' }
        $out = $item.CompletionText.Trim()
        if ($null -eq $item.ResultType) {
            if ($PSCompletions.buffer_after_cursor -match '^\s+[^\s]') {
                return $out
            }
            return "$out$suffix"
        }
        if ($item.ResultType -in
            [System.Management.Automation.CompletionResultType]::Method,
            [System.Management.Automation.CompletionResultType]::Property,
            [System.Management.Automation.CompletionResultType]::Variable,
            [System.Management.Automation.CompletionResultType]::Type,
            [System.Management.Automation.CompletionResultType]::Namespace
        ) {
            return $out
        }
        # Directory, registry key, or other container types
        $_out = $null
        if ($item.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            if ($PSCompletions.config.enable_path_trailing_separator) {
                if ($out.Length -ge 1 -and $out[-1] -match "^['`"]$") {
                    if ($out.Length -ge 2 -and $out[-2] -match '^[/\\]$') {
                        $_out = $out
                    }
                    else {
                        $_out = $out.Insert($out.Length - 1, [System.IO.Path]::DirectorySeparatorChar)
                    }
                }
                else {
                    $_out = $out + [System.IO.Path]::DirectorySeparatorChar
                }
            }
            else {
                $_out = $out
            }
        }
        if ($_out) {
            $lastChar = $_out[-1]
            $afterMatch = [regex]::Matches($PSCompletions.buffer_after_cursor, $PSCompletions.input_pattern)
            if ($afterMatch.Count -gt 0 -and $lastChar -in '"', "'" -and $lastChar -eq $afterMatch[0].Value) {
                return $_out -replace "$lastChar`$", ''
            }
            return $_out
        }

        if ($PSCompletions.buffer_after_cursor -match '^\s+[^\s]') {
            return $out
        }
        else {
            $lastChar = $out[-1]
            $afterMatch = [regex]::Matches($PSCompletions.buffer_after_cursor, $PSCompletions.input_pattern)
            if ($afterMatch.Count -gt 0 -and $lastChar -in '"', "'" -and $lastChar -eq $afterMatch[0].Value) {
                return $out -replace "$lastChar`$", ''
            }
        }
        return "$out$suffix"
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod menu_binary -Force {
        if ($null -ne $PSCompletions.menu.menu_binary_cache) { return $PSCompletions.menu.menu_binary_cache }
        $binRoot = [System.IO.Path]::Combine($PSCompletions.path.root, 'bin')
        $platform = if ($PSEdition -eq 'Desktop' -or $IsWindows) { 'windows' } elseif ($IsMacOS) { 'darwin' } else { 'linux' }
        try {
            $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        }
        catch {
            $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'Arm64' } else { 'X64' }
        }
        $archName = if ($arch -match 'ARM64') { 'arm64' } else { 'x64' }
        $ext = if ($platform -eq 'windows') { '.exe' } else { '' }
        $binary = [System.IO.Path]::Combine($binRoot, "$platform-$archName", "psc-menu$ext")
        if (-not [System.IO.File]::Exists($binary)) {
            $PSCompletions.menu.menu_binary_cache = $null
            return
        }
        # nupkg packaging drops the executable bit on Unix; re-apply +x (idempotent, cached)
        if ($platform -ne 'windows') {
            $pscBin = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($binary), 'psc')
            foreach ($b in $binary, $pscBin) {
                if ([System.IO.File]::Exists($b)) {
                    try { & chmod +x $b 2>$null } catch { }
                }
            }
        }
        $PSCompletions.menu.menu_binary_cache = $binary
        $binary
    }
    Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu -Force {
        param($filter_list)
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }
        if (-not $filter_list) { return '' }
        # Build mode: get_completion hands a build context (hashtable with `build`) instead of items;
        # the engine builds + ranks the candidates inside the menu process.
        $isBuild = ($filter_list -is [hashtable]) -and $filter_list.ContainsKey('build')
        $menu = $PSCompletions.menu
        $config = $PSCompletions.config
        $rawUI = $Host.UI.RawUI
        $binary = $menu.menu_binary()
        if (!$binary) { return }
        if ($rawUI.BufferSize.Height -lt 5) {
            [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(" $($PSCompletions.info.min_area)")
            return ''
        }

        # menu_order is set by get_completion; clear it now so it doesn't leak into the next completion
        $menuOrder = $PSCompletions.menu_order
        $PSCompletions.menu_order = $null

        $input = [ordered]@{}
        if ($isBuild) {
            $input.items = @()
            $input.build = $filter_list.build
        }
        else {
            $input.items = @(
                foreach ($item in $filter_list) {
                    $listText = [string]$item.ListItemText
                    @{
                        completion_text = [string]$item.CompletionText
                        list_item_text  = $listText
                        symbol          = [string]$item.symbol
                        tip             = [string]$item.ToolTip
                        usage           = [string]$item.Usage
                        example         = [string]$item.Example
                        result_type     = if ($null -eq $item.ResultType) { $null } else { [int]$item.ResultType }
                    }
                }
            )
        }
        $input.config = [ordered]@{
            filter_hint    = [string]$PSCompletions.info.filter_hint
            flags          = [ordered]@{
                enable_list_loop           = [bool]$config.enable_list_loop
                filter_mode                = [string]$config.filter_mode
                enable_apply_when_single   = [bool]$config.enable_apply_when_single
                enable_apply_when_no_match = [bool]$config.enable_apply_when_no_match
                show_mode                  = [string]$config.show_mode
                color_focus                = [string]$config.color_focus
                color_match                = [string]$config.color_match
            }
            context_switch = [string]$config.switch
            context_stay   = [string]$config.stay
            raw_config     = [ordered]@{
                completion = if ($PSCompletions.config.completion) { $PSCompletions.config.completion[$PSCompletions.cmd] } else { $null }
                global     = $config
                default    = $PSCompletions.default_config
            }
        }
        $input.terminal = [ordered]@{
            cursor   = [ordered]@{ x = [int]$rawUI.CursorPosition.X; y = [int]$rawUI.CursorPosition.Y }
            buffer   = [ordered]@{ w = [int]$rawUI.BufferSize.Width; h = [int]$rawUI.BufferSize.Height }
            window   = [ordered]@{
                top = 0
                h   = [int]$rawUI.BufferSize.Height
            }
            platform = if ($PSEdition -eq 'Desktop' -or $IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        }
        if ($menuOrder) {
            $input.order = [ordered]@{
                history = [string]$menuOrder.history
                cmd     = [string]$menuOrder.cmd
                aliases = @($menuOrder.aliases)
                path    = [string]$menuOrder.path
            }
        }
        $input.order_dir = [string]$PSCompletions.path.order
        $initialFilter = $PSCompletions.menu.initial_filter
        $PSCompletions.menu.initial_filter = $null
        if ($initialFilter) {
            $input.initial_filter = [string]$initialFilter
        }
        try {
            # Visible window: WindowPosition is the window's top row in the buffer; WindowSize is the visible height
            $input.terminal.window.top = [int]$rawUI.WindowPosition.Y
            $input.terminal.window.h = [int]$rawUI.WindowSize.Height
        }
        catch { }

        # Use the module's temp dir, not %TEMP%: external cleaners may delete files the menu is still using; keep menu files separate from module state
        $tmp = $PSCompletions.path.menu
        $PSCompletions.ensure_dir($tmp)
        $id = [System.Guid]::NewGuid().ToString('N')
        $inputPath = [System.IO.Path]::Combine($tmp, "psc-menu-$id-input.json")
        $outputPath = [System.IO.Path]::Combine($tmp, "psc-menu-$id-output.json")
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        try {
            [System.IO.File]::WriteAllText($inputPath, (ConvertTo-Json -InputObject $input -Depth 10 -Compress), $utf8)
        }
        catch {
            # Input write failed: menu can't start, fall back and clean up
            try { Remove-Item -LiteralPath $inputPath -Force -ErrorAction Ignore } catch { }
            return ''
        }

        # The child moves the cursor; save the origin to restore on exit
        $originCursor = $rawUI.CursorPosition
        $savedOutputEncoding = [Console]::OutputEncoding
        try { [Console]::OutputEncoding = $PSCompletions.menu.encoding } catch { }

        $windowTop = [Math]::Max(0, [int]$rawUI.WindowPosition.Y)
        $windowH = [Math]::Max(1, [int]$rawUI.WindowSize.Height)
        $cursorToTop = [Math]::Max(0, [int]$originCursor.Y - $windowTop)
        $cursorToBottom = [Math]::Max(0, $windowTop + $windowH - 1 - [int]$originCursor.Y)
        $menuWillShowAbove = if ([string]$config.show_mode -eq 'auto') { $false }
        else { $cursorToTop -gt $cursorToBottom }

        $bufferSaved = $false
        if ($PSEdition -eq 'Desktop' -or $IsWindows) {
            try {
                if ($menuWillShowAbove) {
                    # Menu above: save only the region above the cursor (a negative offset covers the input line, which is then saved too)
                    $saveEndY = [Math]::Max(0, [int]$originCursor.Y - 1)
                    $origin = $menu.get_menu_buffer(
                        [System.Management.Automation.Host.Coordinates]::new(0, 0),
                        [System.Management.Automation.Host.Coordinates]::new($rawUI.BufferSize.Width - 1, [Math]::Min($saveEndY, $rawUI.BufferSize.Height - 1)))
                }
                else {
                    # Menu below: save the region under the cursor (the input line stays untouched)
                    $saveStartY = [Math]::Max(0, [int]$originCursor.Y + 1)
                    $saveStartY = [Math]::Min($saveStartY, $rawUI.BufferSize.Height - 1)
                    $origin = $menu.get_menu_buffer(
                        [System.Management.Automation.Host.Coordinates]::new(0, $saveStartY),
                        [System.Management.Automation.Host.Coordinates]::new($rawUI.BufferSize.Width - 1, $rawUI.BufferSize.Height - 1))
                }
                $bufferSaved = $true
            }
            catch {
                # Buffer read failed: skip save/restore, degrade gracefully
                $bufferSaved = $false
            }
        }

        $result = $null
        $errorMsg = $null
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $binary
            $psi.Arguments = "`"$inputPath`" --result `"$outputPath`""
            $psi.UseShellExecute = $false
            $psi.WorkingDirectory = $PWD.Path
            # No CreateNoWindow so the child inherits the console to read keypresses
            $psi.RedirectStandardError = $true
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $process = [System.Diagnostics.Process]::Start($psi)
            $stderr = $process.StandardError
            while (-not $process.HasExited) {
                $lineTask = $stderr.ReadLineAsync()
                if (-not $lineTask.Wait(30000)) {
                    try { $process.Kill() } catch { }
                    try {
                        $esc = [char]27
                        [Console]::Out.Write("$esc[?1049l")
                    }
                    catch { }
                    $errorMsg = 'menu timed out'
                    break
                }
                $line = $lineTask.Result
                if ($null -eq $line) { break }
            }
            # Bounded wait for full exit; Kill on abnormal residue so Tab never hangs
            if (-not $process.WaitForExit(30000)) {
                try { $process.Kill() } catch { }
                $errorMsg = 'menu timed out'
            }
            if ([System.IO.File]::Exists($outputPath)) {
                $result = [System.IO.File]::ReadAllText($outputPath, $utf8) | ConvertFrom-Json
            }
            elseif ($errorMsg) {
            }
            else {
                $result = @{ status = 'cancel' }
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
        }
        finally {
            # Restore the saved buffer region on every non-alternate exit. When the menu reported
            # a covered range, restore exactly that. When it died abnormally (timeout / crash /
            # missing result) it may have drawn content without reporting coverage — restore the
            # whole saved region so no residue is left. A normal cancel (no error, no coverage)
            # means nothing was rendered, so skip the restore (writing it back would trigger
            # PSReadLine to repaint its prediction list).
            if ($bufferSaved -and -not ($result -and $result.alternate)) {
                try {
                    $hasCovered = $result -and $null -ne $result.covered_top -and $null -ne $result.covered_bottom
                    if ($hasCovered -or $errorMsg) {
                        if ($hasCovered) {
                            $top = [int]$result.covered_top
                            $bottom = [int]$result.covered_bottom
                        }
                        else {
                            $top = [int]$origin.top.Y
                            $bottom = [int]$origin.bottom.Y
                        }
                        if ($bottom -ge $top -and $bottom -lt [int]$rawUI.BufferSize.Height) {
                            $w = [int]$rawUI.BufferSize.Width
                            $h = $bottom - $top + 1
                            $sub = New-Object 'System.Management.Automation.Host.BufferCell[,]' $h, $w
                            $offsetY = $top - [int]$origin.top.Y
                            # 2D arrays need GetValue/SetValue: `$arr[$r, $c]` flattens, and `$i + $r, $c` triggers op_Addition
                            for ($r = 0; $r -lt $h; $r++) {
                                for ($c = 0; $c -lt $w; $c++) {
                                    $sub.SetValue($origin.buffer.GetValue($offsetY + $r, $c), $r, $c)
                                }
                            }
                            $rawUI.SetBufferContents(
                                [System.Management.Automation.Host.Coordinates]::new(0, $top),
                                $sub)
                        }
                    }
                }
                catch { }
            }
            # Retry deletes briefly (antivirus etc.); try/catch covers files already gone or never written
            foreach ($p in @($inputPath, $outputPath)) {
                for ($i = 0; $i -lt 3 -and [System.IO.File]::Exists($p); $i++) {
                    try { Remove-Item -LiteralPath $p -Force } catch { Start-Sleep -Milliseconds 100 }
                }
            }
            # Restore encoding/cursor in finally so a throw mid-menu still recovers both.
            # Restore the cursor on every platform: the alternate-screen leave only returns the
            # terminal to the main screen; repositioning the cursor back to the input line is our
            # job (on Windows the menu also leaves it at the last drawn spot otherwise).
            try { [Console]::OutputEncoding = $savedOutputEncoding } catch { }
            try { $rawUI.CursorPosition = $originCursor } catch { }
        }
        if ($result) {
            switch ($result.status) {
                'selected' {
                    if ($isBuild) {
                        # Build mode: the engine returns the selected item's text/type (no host item list)
                        return $menu.handle_menu_output(@{ CompletionText = $result.completion_text; ResultType = $result.result_type })
                    }
                    return $menu.handle_menu_output($filter_list[$result.index])
                }
                'cancel' { return '' }
                'input' { return [string]$result.text }
                'min_area' {
                    [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert(" $($PSCompletions.info.min_area)")
                    return ''
                }
                default { $errorMsg = if ($result.message) { [string]$result.message } else { 'unexpected status' } }
            }
        }
        if ($errorMsg) {
            # Write-Error renders below the input line (not on it); SilentlyContinue neutralizes session-level $ErrorActionPreference
            Microsoft.PowerShell.Utility\Write-Error -Message "[PSCompletions] menu unavailable: $errorMsg" -ErrorAction SilentlyContinue
            return
        }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod apply_completions_sort -Force {
        param([string]$cmd, [object]$filter_list, [array]$tokens, [bool]$treatLastAsComplete)
        if (!$filter_list) { return $filter_list }
        $PSCompletions.set_menu_order($cmd)
        if (!$PSCompletions.config.enable_sort_by_history) { return $filter_list }
        $items = @(
            foreach ($item in $filter_list) {
                @{ text = [string]$item.CompletionText }
            }
        )
        $sortInput = @{
            items                  = $items
            order                  = @{
                cmd_order      = "$($PSCompletions.path.order)/$([uri]::EscapeDataString($cmd)).json"
                paths_order    = "$($PSCompletions.path.order)/_shared/_paths.json"
                commands_order = "$($PSCompletions.path.order)/_shared/_commands.json"
            }
            tokens                 = $tokens
            treat_last_as_complete = $treatLastAsComplete
        }
        $sorted = $PSCompletions.run_sort($sortInput)
        if ($null -eq $sorted -or $sorted.Count -eq 0) { return $filter_list }
        $textOrder = @{}
        for ($i = 0; $i -lt $sorted.Count; $i++) { $textOrder[[string]$sorted[$i].text] = $i }
        $filter_list = @($filter_list | Sort-Object {
                $idx = $textOrder[[string]$_.CompletionText]
                if ($null -eq $idx) { [int]::MaxValue } else { $idx }
            })
        $filter_list
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod set_menu_order -Force {
        param([string]$cmd)
        if (!$PSCompletions.config.enable_sort_by_history) { return }
        $orderAliases = @($PSCompletions.data.alias[$cmd]).Where({ $_ })
        if (-not $orderAliases) { $orderAliases = @($cmd) }
        $PSCompletions.menu_order = @{
            history = (Get-PSReadLineOption).HistorySavePath
            cmd     = $cmd
            aliases = $orderAliases
            path    = "$($PSCompletions.path.order)/$([uri]::EscapeDataString($cmd)).json"
        }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_completion -Force {
        param([string]$cmd, [array]$inputs)
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

        if ($null -eq $cmd) { return }

        $language = $PSCompletions.get_language($cmd)
        $manifest = "$($PSCompletions.path.completions)/$cmd/language/$language.json"
        $hooksLuaPath = "$($PSCompletions.path.completions)/$cmd/hooks.lua"
        # enable_hooks gate: per-completion override (0 disables it); psc itself always runs
        $hasLuaHooks = [System.IO.File]::Exists($hooksLuaPath)
        if ($hasLuaHooks -and $cmd -ne 'psc' -and $PSCompletions.config.completion) {
            $hasLuaHooks = $PSCompletions.config.completion[$cmd].enable_hooks -ne 0
        }
        $argTokens = if ($inputs.Count -le 1) { , @() } else { $inputs[1..($inputs.Count - 1)] }
        # psc completion needs module-level data (paths + live config)
        $pscData = $null
        if ($cmd -eq 'psc') {
            $pscData = @{
                settings         = $PSCompletions.path.data
                completions_json = $PSCompletions.path.completions_json
                completions      = $PSCompletions.path.completions
                config           = @{
                    language   = $PSCompletions.config.language
                    completion = $PSCompletions.config.completion
                }
            }
        }
        $orderInfo = $null
        if ($PSCompletions.config.enable_sort_by_history) {
            $orderInfo = @{
                cmd_order      = "$($PSCompletions.path.order)/$([uri]::EscapeDataString($cmd)).json"
                paths_order    = "$($PSCompletions.path.order)/_shared/_paths.json"
                commands_order = "$($PSCompletions.path.order)/_shared/_commands.json"
            }
        }
        $buildContext = @{
            cmd                    = $cmd
            arg_tokens             = @($argTokens)
            treat_last_as_complete = [bool]($PSCompletions.buffer_before_cursor[-1] -eq ' ')
            manifest               = $manifest
            hooks                  = [bool]$hasLuaHooks
            cwd                    = $PWD.Path
            config                 = $PSCompletions.config.completion[$cmd]
            global_config          = $PSCompletions.config
            data                   = $pscData
            order                  = $orderInfo
            cache_dir              = $PSCompletions.path.cache
            log_dir                = $PSCompletions.path.log
        }
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($cmd)) {
            return ''
        }
        # The engine builds and ranks the candidates inside the menu process (build mode).
        $PSCompletions.set_menu_order($cmd)
        return @{ build = $buildContext }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod run_sort -Force {
        param([hashtable]$sortInput)
        $binary = $PSCompletions.menu.menu_binary()
        if (!$binary) { return }
        $tmp = $PSCompletions.path.menu
        $PSCompletions.ensure_dir($tmp)
        $id = [System.Guid]::NewGuid().ToString('N')
        $inputPath = [System.IO.Path]::Combine($tmp, "psc-menu-$id-sort-in.json")
        $outputPath = [System.IO.Path]::Combine($tmp, "psc-menu-$id-sort-out.json")
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($inputPath, (ConvertTo-Json -InputObject $sortInput -Depth 10 -Compress), $utf8)
        $process = $null
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $binary
            $psi.Arguments = "--sort `"$inputPath`" --result `"$outputPath`""
            $psi.UseShellExecute = $false
            $psi.WorkingDirectory = $PWD.Path
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardError = $true
            $process = [System.Diagnostics.Process]::Start($psi)
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if ($process.WaitForExit(15000)) {
                $null = $stderrTask.Result
                if ($process.ExitCode -eq 0 -and [System.IO.File]::Exists($outputPath)) {
                    return ([System.IO.File]::ReadAllText($outputPath, $utf8) | ConvertFrom-Json)
                }
                return
            }
            try { $null = $stderrTask.Result } catch { }
            return
        }
        catch { return }
        finally {
            try { if ($null -ne $process -and !$process.HasExited) { $process.Kill() } } catch { }
            Remove-Item $inputPath, $outputPath -Force -ErrorAction Ignore
        }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod render_pending -Force {
        try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }
        # Pending module/library notifications appended AFTER a psc command's output. Not one-shot:
        # a newer module version and pending updates persist until the user acts on them.
        $showLibrary = -not $PSCompletions.pending_skip_library
        $PSCompletions.pending_skip_library = $false
        # Module update: change.json's module field records the newest remote version the CLI fetched.
        $changeJson = $PSCompletions.path.change
        $json = $PSCompletions.get_raw_content($changeJson)
        if ($json) {
            $changes = $null
            try { $changes = $PSCompletions.ConvertFrom_JsonAsHashtable($json) } catch { }
            if ($null -ne $changes -and $changes.module) {
                $newVersion = [string]$changes.module
                try { $isNewer = [version]$newVersion -gt [version]$PSCompletions.version } catch { $isNewer = $false }
                if ($isNewer) {
                    $PSCompletions.new_version = $newVersion
                    $template = $PSCompletions.info.module.update
                    if (-not $template) {
                        try {
                            $pscLang = $PSCompletions.get_language('psc')
                            $pscData = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/psc/language/$pscLang.json"))
                            if ($pscData.info.module.update) { $template = $pscData.info.module.update }
                        }
                        catch { }
                    }
                    if ($template) {
                        $PSCompletions.write_with_color($PSCompletions.replace_content($template))
                    }
                }
                else {
                    # No longer newer (the user upgraded the module externally): drop the stale module field.
                    $changes.Remove('module')
                    try {
                        [System.IO.File]::WriteAllText(
                            $changeJson,
                            ($changes | ConvertTo-Json -Depth 6 -Compress),
                            [System.Text.Encoding]::UTF8)
                    }
                    catch { }
                }
            }
        }
        if ($showLibrary) {
            $PSCompletions.render_library_changes()
        }
    }
    Add-Member -InputObject $PSCompletions -MemberType ScriptMethod init_data -Force {
        $PSCompletions.lang_cache = @{}
        $pscBinary = $PSCompletions.psc_binary()
        if (!$pscBinary) {
            $PSCompletions.write_binary_error()
            $PSCompletions.binary_ok = $false
            return
        }
        $dataDir = [System.IO.Path]::GetDirectoryName($PSCompletions.path.data)
        $tmp = $PSCompletions.path.menu
        $PSCompletions.ensure_dir($tmp)
        $id = [System.Guid]::NewGuid().ToString('N')
        $initPath = [System.IO.Path]::Combine($tmp, "psc-init-$id.json")
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        # All init data (settings/aliases/index/URL/info) is provided by psc init — a single source of truth
        & $pscBinary --data $dataDir --language $PSUICulture init --result $initPath 2>$null
        if ($LASTEXITCODE -ne 0 -or ![System.IO.File]::Exists($initPath)) {
            Remove-Item $initPath -Force -ErrorAction SilentlyContinue
            $PSCompletions.write_binary_error()
            $PSCompletions.binary_ok = $false
            return
        }
        $all = $PSCompletions.ConvertFrom_JsonAsHashtable([System.IO.File]::ReadAllText($initPath, $utf8))
        Remove-Item $initPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $all -or $null -eq $all.data) {
            $PSCompletions.write_binary_error()
            $PSCompletions.binary_ok = $false
            return
        }
        $PSCompletions.data = $all.data
        $PSCompletions.data.aliasMap = $all.aliasMap
        $PSCompletions.data.list = @($PSCompletions.data.alias.Keys)
        $PSCompletions.default_config = $all.default_config
        $PSCompletions.config = $PSCompletions.data.config
        if ($PSCompletions.config -is [hashtable] -and $PSCompletions.default_config -is [hashtable]) {
            foreach ($k in $PSCompletions.default_config.Keys) {
                if (-not $PSCompletions.config.ContainsKey($k)) {
                    $PSCompletions.config[$k] = $PSCompletions.default_config[$k]
                }
            }
        }
        $PSCompletions.language = $PSCompletions.config.language
        $PSCompletions.urls = @($all.urls)
        $PSCompletions.list = @($all.list)
        $PSCompletions.info = $all.info
        $PSCompletions.binary_ok = $true
    }
    if (-not $methodsOnly) {
        $PSCompletions.init_data()
        if (-not $PSCompletions.binary_ok) {
            return
        }
        $PSCompletions.handle_completion()
        if ($PSCompletions.config.enable_auto_alias_setup) {
            $Matches = $PSCompletions.data.aliasMap.Keys
            foreach ($_ in $Matches) {
                $args = $PSCompletions.data.aliasMap[$_]
                if ($args -eq 'psc') {
                    Microsoft.PowerShell.Utility\Set-Alias $_ PSCompletions -Force -ErrorAction Ignore -Scope Global
                }
                elseif ($_ -ne $args -and $_ -notmatch '[\\/]') {
                    Microsoft.PowerShell.Utility\Set-Alias $_ $args -Force -ErrorAction Ignore -Scope Global
                }
            }
            $Matches = $null
        }
        else {
            Microsoft.PowerShell.Utility\Set-Alias psc PSCompletions -Force -ErrorAction Ignore -Scope Global
        }
        $PSCompletions.initialized = $true
    }
}

if ([System.IO.File]::Exists($PSCompletions.path.data)) {
    $_ = ConvertFrom-Json ([System.IO.File]::ReadAllText($PSCompletions.path.data)) -ErrorAction SilentlyContinue
    $PSCompletions.psc_alias = $_.alias.PSObject.Properties['psc'].value
    $PSCompletions._key = $_.config.trigger_key
}
else {
    $PSCompletions.psc_alias = @('psc')
    $PSCompletions._key = 'Tab'

    if (![System.IO.Directory]::Exists($PSCompletions.path.order)) {
        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ensure_dir -Force {
            param([string]$path)
            if (![System.IO.Directory]::Exists($path)) { New-Item -ItemType Directory $path -ErrorAction SilentlyContinue | Out-Null }
        }
        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod move_old_version {
            function _moveData {
                param($Dir, $JsonFile, $CompletionsDir)
                $PSCompletions.ensure_dir($CompletionsDir)
                if (![System.IO.File]::Exists($JsonFile) -and [System.IO.File]::Exists("$Dir/data.json")) {
                    Move-Item "$Dir/data.json" $JsonFile -Force -ErrorAction Ignore
                }
                $Dir, $PSCompletions.path.root | ForEach-Object {
                    if ([System.IO.Directory]::Exists("$_/completions")) {
                        Get-ChildItem "$_/completions" -Directory | ForEach-Object { Copy-Item $_.FullName $CompletionsDir -Force -Recurse }
                        Remove-Item "$_/completions" -Force -Recurse -ErrorAction Ignore
                    }
                }
            }
            $version = (Get-ChildItem (Split-Path $PSCompletions.path.root -Parent) -ErrorAction Ignore).Name | Where-Object { $_ -match '^\d+\.\d.*' } | Sort-Object { [Version]$_ }
            if ($null -eq $version) {
                $scoop_persist = Join-Path $PSCompletions.path.root.Replace('\modules\PSCompletions', '') 'persist'
                foreach ($_ in "$scoop_persist/abgox.PSCompletions", "$scoop_persist/pscompletions") {
                    if ([System.IO.Directory]::Exists($_)) { _moveData $_ "$_/data/settings.json" "$_/data/completions" }
                }
                return
            }
            if ($version.Count -ge 2) {
                $oldVerDir = Join-Path (Split-Path $PSCompletions.path.root -Parent) $version[-2]
                if ([System.IO.Directory]::Exists("$oldVerDir/data")) { Move-Item "$oldVerDir/data" $PSCompletions.path.root -Force -ErrorAction Ignore }
            }
            else {
                $oldVerDir = $PSCompletions.path.root
            }
            _moveData $oldVerDir $PSCompletions.path.data $PSCompletions.path.completions
        }
        $PSCompletions.move_old_version()
        $PSCompletions.ensure_dir($PSCompletions.path.order)
        if ([System.IO.File]::Exists($PSCompletions.path.data)) {
            $_ = ConvertFrom-Json ([System.IO.File]::ReadAllText($PSCompletions.path.data)) -ErrorAction SilentlyContinue
            $PSCompletions.psc_alias = $_.alias.PSObject.Properties['psc'].value
            $PSCompletions._key = $_.config.trigger_key
        }
    }
}
foreach ($_ in $PSCompletions.psc_alias) {
    Microsoft.PowerShell.Utility\Set-Alias $_ PSCompletions -Force -ErrorAction Ignore -Scope Global
}
Set-PSReadLineKeyHandler -Key $PSCompletions._key -ScriptBlock $PSCompletions.menu.module_completion_menu_script
