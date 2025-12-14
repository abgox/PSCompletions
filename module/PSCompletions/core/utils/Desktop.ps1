$PSCompletions.methods['ConvertFrom_JsonAsHashtable'] = {
    param([string]$json)

    # https://github.com/abgox/ConvertFrom-JsonAsHashtable
    function ConvertFrom-JsonAsHashtable {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject
        )

        begin {
            $buffer = [System.Text.StringBuilder]::new()
        }

        process {
            if ($InputObject -is [array]) {
                [void]$buffer.AppendLine(($InputObject -join "`n"))
            }
            else {
                [void]$buffer.AppendLine($InputObject)
            }
        }

        end {
            $jsonString = $buffer.ToString().Trim()
            if (-not $jsonString) { return $null }

            if ($PSVersionTable.PSVersion.Major -ge 7) {
                return ConvertFrom-Json $jsonString -AsHashtable
            }

            $jsonString = [regex]::Replace($jsonString, '(?<!\\)""\s*:', { '"emptyKey_' + [Guid]::NewGuid() + '":' })

            $jsonString = [regex]::Replace($jsonString, ',\s*(?=[}\]]\s*$)', '')

            $parsed = ConvertFrom-Json $jsonString

            function ConvertRecursively {
                param($obj)

                if ($null -eq $obj) { return $null }

                # IDictionary (Hashtable, Dictionary<,>) -> @{ }
                if ($obj -is [System.Collections.IDictionary]) {
                    $ht = @{}
                    $keys = $obj.Keys
                    foreach ($k in $keys) {
                        $ht[$k] = ConvertRecursively $obj[$k]
                    }
                    return $ht
                }

                # PSCustomObject -> @{ }
                if ($obj -is [System.Management.Automation.PSCustomObject]) {
                    $ht = @{}
                    $props = $obj.PSObject.Properties
                    foreach ($p in $props) {
                        $ht[$p.Name] = ConvertRecursively $p.Value
                    }
                    return $ht
                }

                # IEnumerable (array、ArrayList), exclude string and byte[]
                if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string]) -and -not ($obj -is [byte[]])) {
                    $list = [System.Collections.Generic.List[object]]::new()
                    foreach ($item in $obj) {
                        $list.Add((ConvertRecursively $item))
                    }
                    return , $list.ToArray()
                }

                # ohter types (string, int, bool, datetime...)
                return $obj
            }

            return ConvertRecursively $parsed
        }
    }

    ConvertFrom-JsonAsHashtable $json
}
$PSCompletions.methods['start_job'] = {
    $PSCompletions.job = Start-Job -ScriptBlock {
        param($PSCompletions)

        # https://github.com/abgox/ConvertFrom-JsonAsHashtable
        function ConvertFrom_JsonAsHashtable {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline = $true)]
                $InputObject
            )

            begin {
                $buffer = [System.Text.StringBuilder]::new()
            }

            process {
                if ($InputObject -is [array]) {
                    [void]$buffer.AppendLine(($InputObject -join "`n"))
                }
                else {
                    [void]$buffer.AppendLine($InputObject)
                }
            }

            end {
                $jsonString = $buffer.ToString().Trim()
                if (-not $jsonString) { return $null }

                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    return ConvertFrom-Json $jsonString -AsHashtable
                }

                $jsonString = [regex]::Replace($jsonString, '(?<!\\)""\s*:', { '"emptyKey_' + [Guid]::NewGuid() + '":' })

                $jsonString = [regex]::Replace($jsonString, ',\s*(?=[}\]]\s*$)', '')

                $parsed = ConvertFrom-Json $jsonString

                function ConvertRecursively {
                    param($obj)

                    if ($null -eq $obj) { return $null }

                    # IDictionary (Hashtable, Dictionary<,>) -> @{ }
                    if ($obj -is [System.Collections.IDictionary]) {
                        $ht = @{}
                        $keys = $obj.Keys
                        foreach ($k in $keys) {
                            $ht[$k] = ConvertRecursively $obj[$k]
                        }
                        return $ht
                    }

                    # PSCustomObject -> @{ }
                    if ($obj -is [System.Management.Automation.PSCustomObject]) {
                        $ht = @{}
                        $props = $obj.PSObject.Properties
                        foreach ($p in $props) {
                            $ht[$p.Name] = ConvertRecursively $p.Value
                        }
                        return $ht
                    }

                    # IEnumerable (array、ArrayList), exclude string and byte[]
                    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string]) -and -not ($obj -is [byte[]])) {
                        $list = [System.Collections.Generic.List[object]]::new()
                        foreach ($item in $obj) {
                            $list.Add((ConvertRecursively $item))
                        }
                        return , $list.ToArray()
                    }

                    # ohter types (string, int, bool, datetime...)
                    return $obj
                }

                return ConvertRecursively $parsed
            }
        }

        function get_raw_content {
            param ([string]$path, [bool]$trim = $true)
            $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
            if ($res) {
                if ($trim) { return $res.Trim() }
                return $res
            }
            ''
        }

        function download_file {
            param(
                [string]$path, # 相对于 $baseUrl 的文件路径
                [string]$file,
                [array]$baseUrl
            )
            $isErr = $true
            for ($i = 0; $i -lt $baseUrl.Count; $i++) {
                $item = $baseUrl[$i]
                $url = $item + '/' + $path
                try {
                    Invoke-RestMethod -Uri $url -OutFile $file -TimeoutSec 30 -ErrorAction Stop
                    $isErr = $false
                    break
                }
                catch {}
            }
            if ($isErr) {
                throw
            }
        }
        function ensure_dir {
            param([string]$path)
            if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
        }
        function download_list {
            ensure_dir $PSCompletions.path.temp
            if (!(Test-Path $PSCompletions.path.completions_json)) {
                @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
            }
            $current_list = (get_raw_content $PSCompletions.path.completions_json | ConvertFrom-Json).list
            foreach ($url in $PSCompletions.urls) {
                try {
                    $response = Invoke-RestMethod -Uri "$url/completions.json" -TimeoutSec 30 -ErrorAction Stop

                    $remote_list = $response.list

                    $diff = Compare-Object $remote_list $current_list -PassThru
                    if ($diff) {
                        $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8
                        $response | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
                        $PSCompletions.list = $remote_list
                    }
                    else {
                        Clear-Content $PSCompletions.path.change -Force
                        $PSCompletions.list = $current_list
                    }
                    return $remote_list
                }
                catch {}
            }
            throw
        }

        ensure_dir $PSCompletions.path.order
        ensure_dir "$($PSCompletions.path.completions)/psc"

        $null = download_list

        # data.json
        $data = [ordered]@{
            list     = @()
            alias    = [ordered]@{}
            aliasMap = [ordered]@{}
            config   = [ordered]@{}
        }
        $data.config.comp_config = [ordered]@{}
        $items = Get-ChildItem -Path $PSCompletions.path.completions
        foreach ($_ in $items) {
            $cmd = $_.Name
            $data.list += $cmd

            $data.alias[$cmd] = @()
            $alias = $PSCompletions.data.alias[$cmd]
            if ($null -ne $alias) {
                foreach ($a in $alias) {
                    $data.alias[$cmd] += $a
                    $data.aliasMap[$a] = $cmd
                }
            }
            else {
                $data.alias[$cmd] += $cmd
                $data.aliasMap[$cmd] = $cmd
            }

            ## config.comp_config
            $completion = $cmd
            $config = $PSCompletions.config.comp_config[$completion]
            $data.config.comp_config[$completion] = [ordered]@{}
            if ($config) {
                $keys = $config.Keys
                foreach ($c in $keys) {
                    $data.config.comp_config[$completion].$c = $config.$c
                }
            }
        }

        ## config
        $keys = $PSCompletions.default_config.Keys
        foreach ($c in $keys) {
            if ($PSCompletions.config[$c] -ne $null) {
                $data.config[$c] = $PSCompletions.config[$c]
            }
            else {
                $data.config[$c] = $PSCompletions.default_config[$c]
            }
        }

        foreach ($_ in $PSCompletions.data.list) {
            if ($data.config.comp_config[$_] -eq $null) {
                $data.config.comp_config[$_] = [ordered]@{}
            }
            $path = "$($PSCompletions.path.completions)/$_/config.json"
            if (!(Test-Path $path)) {
                try {
                    download_file "completions/$_/config.json" $path $PSCompletions.urls
                }
                catch {
                    continue
                }
            }
            ensure_dir "$($PSCompletions.path.completions)/$_/language"
            $json_config = get_raw_content $path | ConvertFrom-Json
            foreach ($lang in $json_config.language) {
                $path_lang = "$($PSCompletions.path.completions)/$_/language/$lang.json"
                if (!(Test-Path $path_lang)) {
                    download_file "completions/$_/language/$lang.json" $path_lang $PSCompletions.urls
                }
            }
            if ($json_config.hooks -ne $null) {
                $path_hooks = "$($PSCompletions.path.completions)/$_/hooks.ps1"
                if (!(Test-Path $path_hooks)) {
                    download_file "completions/$_/hooks.ps1" $path_hooks $PSCompletions.urls
                }
                if ($data.config.comp_config[$_].enable_hooks -eq $null) {
                    $data.config.comp_config[$_].enable_hooks = [int]$json_config.hooks
                }
            }
            $path = "$($PSCompletions.path.completions)/$_/language/$($json_config.language[0]).json"
            $json = get_raw_content $path | ConvertFrom_JsonAsHashtable
            $config_list = $PSCompletions.default_completion_item
            foreach ($item in $config_list) {
                if ($data.config.comp_config[$_].$item -eq '') {
                    $data.config.comp_config[$_].Remove($item)
                }
            }
            foreach ($item in $json.config) {
                $config_list += $item.name
                if ($data.config.comp_config[$_].$($item.name) -eq $null) {
                    $data.config.comp_config[$_].$($item.name) = $item.value
                }
                else {
                    if ($data.config.comp_config[$_].$($item.name) -eq '' -and $item.value -ne '' -and '' -notin $item.values) {
                        $data.config.comp_config[$_].$($item.name) = $item.value
                    }
                }
            }
            $keys = $data.config.comp_config[$_].Keys.Where({ $_ -notin $config_list })
            foreach ($r in $keys) {
                if ($r -eq 'enable_hooks') {
                    if ($json_config.hooks -eq $null) {
                        $data.config.comp_config[$_].Remove($r)
                    }
                }
                else {
                    $data.config.comp_config[$_].Remove($r)
                }
            }
        }
        $keys = $data.config.comp_config.Keys
        $need_rm = @()
        foreach ($k in $keys) {
            if (!$data.config.comp_config[$k].Count) {
                $need_rm += $k
            }
        }
        foreach ($_ in $need_rm) {
            $data.config.comp_config.Remove($_)
        }

        $new_data = $data | ConvertTo-Json -Depth 5 -Compress
        $old_data = get_raw_content $PSCompletions.path.data | ConvertFrom-Json | ConvertTo-Json -Depth 5 -Compress
        if ($new_data -ne $old_data) {
            $new_data | Out-File $PScompletions.path.data -Force -Encoding utf8
        }

        function check_update {
            $currentTime = Get-Date
            $updateInterval = [TimeSpan]::FromDays(1)

            if (Test-Path $PSCompletions.path.last_update) {
                $lastUpdate = Get-Content $PSCompletions.path.last_update | Get-Date
                if ($lastUpdate) {
                    $timeSinceLast = $currentTime - $lastUpdate
                    if ($timeSinceLast -lt $updateInterval) {
                        return
                    }
                }
            }

            # check module version
            try {
                if ($PSCompletions.config.enable_module_update) {
                    $urls = $PSCompletions.urls + "https://pscompletions.abgox.com"
                    foreach ($url in $urls) {
                        try {
                            $res = Invoke-RestMethod -Uri "$url/module/version.json" -TimeoutSec 30 -ErrorAction Stop
                            $newVersion = $res.version
                            break
                        }
                        catch {}
                    }
                    $newVersion = $newVersion -replace 'v', ''
                    if ($newVersion -match "^[\d\.]+$") {
                        $currentTime.ToString('o') | Out-File $PSCompletions.path.last_update -Force -Encoding utf8

                        $versions = @($PSCompletions.version, $newVersion) | Sort-Object { [Version] $_ }
                        if ($versions[-1] -ne $PSCompletions.version) {
                            $data = get_raw_content $PSCompletions.path.data | ConvertFrom_JsonAsHashtable
                            $data.config.enable_module_update = $versions[-1]
                            $data | ConvertTo-Json -Depth 5 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
                        }
                    }
                }
            }
            catch {}

            # check completions update
            if ($PSCompletions.config.enable_completions_update) {
                $update_list = @()
                $check_list = (Get-ChildItem $PSCompletions.path.completions -ErrorAction SilentlyContinue).Where({ $_.Name -in $PSCompletions.list })
                foreach ($_ in $check_list) {
                    $isErr = $true
                    foreach ($url in $PSCompletions.urls) {
                        try {
                            $response = Invoke-RestMethod -Uri "$url/completions/$($_.Name)/guid.json" -TimeoutSec 30 -ErrorAction Stop
                            $isErr = $false
                            break
                        }
                        catch {}
                    }
                    if ($isErr) {
                        continue
                    }
                    try {
                        $guid_path = "$($PSCompletions.path.completions)/$($_.Name)/guid.json"
                        if (Test-Path $guid_path) {
                            $old_guid = get_raw_content $guid_path | ConvertFrom-Json | Select-Object -ExpandProperty guid
                            if ($response.guid -ne $old_guid) {
                                $update_list += $_.Name
                            }
                        }
                        else {
                            $update_list += $_.Name
                        }
                    }
                    catch {}
                }
                if ($update_list) { $update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8 }
                else { Clear-Content $PSCompletions.path.update -Force -ErrorAction SilentlyContinue }
            }
        }
        check_update

        function getCompletions {
            $guid = $PSCompletions.guid
            $obj = @{}

            # XXX: 这里必须是引用类型
            $special_options = @{
                WriteSpaceTab              = @()
                WriteSpaceTab_and_SpaceTab = @()
            }
            function parseJson($cmds, $obj, [string]$cmdO, [switch]$isOption) {
                if ($obj[$cmdO].$guid -eq $null) {
                    $obj[$cmdO] = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
                    $obj[$cmdO].$guid = @()
                }
                foreach ($cmd in $cmds) {
                    $name = $cmd.name
                    $next = $cmd.next
                    $options = $cmd.options

                    $symbols = @()
                    if ($isOption) {
                        if ($next -eq $null -and $options -eq $null) {
                            $symbols += 'OptionTab'
                        }
                        else {
                            $symbols += 'WriteSpaceTab'
                            if ($next -is [array] -or $options -is [array]) {
                                $symbols += 'SpaceTab'
                            }
                        }
                    }
                    else {
                        if ($next -is [array] -or $options -is [array]) {
                            $symbols += 'SpaceTab'
                        }
                    }

                    $tip = $cmd.tip
                    $alias = $cmd.alias

                    $alias_list = $alias + $name

                    # hide 值为 true 的补全将被过滤掉，用于配合 hooks.ps1 中添加动态补全
                    # 如果不过滤掉，会和 hooks.ps1 中添加的动态补全产生重复
                    if (!$cmd.hide) {
                        $obj[$cmdO].$guid += @{
                            CompletionText = $name
                            ListItemText   = $name
                            ToolTip        = $tip
                            symbols        = $symbols
                            alias          = $alias_list
                        }

                        foreach ($a in $alias) {
                            $obj[$cmdO].$guid += @{
                                CompletionText = $a
                                ListItemText   = $a
                                ToolTip        = $tip
                                symbols        = $symbols
                                alias          = $alias_list
                            }
                        }
                    }

                    if ($symbols) {
                        if ('WriteSpaceTab' -in $symbols) {
                            $pad = if ($cmdO -in @('rootOptions', 'commonOptions')) { ' ' }else { $cmdO + ' ' }
                            $special_options.WriteSpaceTab += $pad + $name
                            foreach ($a in $alias) { $special_options.WriteSpaceTab += $pad + $a }
                            if ('SpaceTab' -in $symbols) {
                                $special_options.WriteSpaceTab_and_SpaceTab += $pad + $name
                                foreach ($a in $alias) { $special_options.WriteSpaceTab_and_SpaceTab += $pad + $a }
                            }
                        }
                    }
                    if ($options) {
                        parseJson $options $obj[$cmdO] $name -isOption
                        foreach ($a in $alias) {
                            parseJson $options $obj[$cmdO] $a -isOption
                        }
                    }
                    if ($next -or 'WriteSpaceTab' -in $symbols) {
                        parseJson $next $obj[$cmdO] $name
                        foreach ($a in $alias) {
                            parseJson $next $obj[$cmdO] $a
                        }
                    }
                }
            }
            if ($_completions[$root].root) {
                parseJson $_completions[$root].root $obj 'root'
            }
            if ($_completions[$root].options) {
                parseJson $_completions[$root].options $obj 'rootOptions' -isOption
            }
            if ($_completions[$root].common_options) {
                parseJson $_completions[$root].common_options $obj 'commonOptions' -isOption
            }
            $_completions_data."$($root)_WriteSpaceTab" = $special_options.WriteSpaceTab | Select-Object -Unique
            $_completions_data."$($root)_WriteSpaceTab_and_SpaceTab" = $special_options.WriteSpaceTab_and_SpaceTab | Select-Object -Unique
            $_completions_data."$($root)_common_options" = $obj.commonOptions.$guid.CompletionText
            return $obj
        }
        function get_language {
            param ([string]$completion)

            $path_config = "$($PSCompletions.path.completions)/$completion/config.json"
            $content_config = get_raw_content $path_config | ConvertFrom-Json

            if (!$content_config.language) {
                download_file "completions/$completion/config.json" $path_config $PSCompletions.urls
                $content_config = get_raw_content $path_config | ConvertFrom-Json
            }
            ensure_dir "$($PSCompletions.path.completions)/$completion/language"
            foreach ($lang in $content_config.language) {
                $path_lang = "$($PSCompletions.path.completions)/$completion/language/$lang.json"
                if (!(Test-Path $path_lang)) {
                    download_file "completions/$completion/language/$lang.json" $path_lang $PSCompletions.urls
                }
            }
            if ($content_config.hooks -ne $null) {
                $path_hooks = "$($PSCompletions.path.completions)/$completion/hooks.ps1"
                if (!(Test-Path $path_hooks)) {
                    download_file "completions/$completion/hooks.ps1" $path_hooks $PSCompletions.urls
                }
            }
            $lang = $PSCompletions.config.comp_config[$completion].language
            if ($lang) {
                $config_language = $lang
            }
            else {
                $config_language = $null
            }
            if ($config_language) {
                $language = if ($config_language -in $content_config.language) { $config_language }else { $content_config.language[0] }
            }
            else {
                $language = if ($PSCompletions.language -in $content_config.language) { $PSCompletions.language }else { $content_config.language[0] }
            }
            $language
        }

        $_completions = @{}
        $_completions_data = @{}
        $time = (Get-Date).AddMonths(-6)
        $filter = (Get-ChildItem $PSCompletions.path.order).Where({ $_.LastWriteTime -gt $time })
        foreach ($_ in $filter) {
            $root = $_.BaseName
            if ($root -in $PSCompletions.data.list) {
                try {
                    $language = get_language $root
                }
                catch {
                    continue
                }
                $path_language = "$($PSCompletions.path.completions)/$root/language/$language.json"
                if (Test-Path $path_language) {
                    $_completions[$root] = get_raw_content $path_language | ConvertFrom_JsonAsHashtable
                    $_completions_data[$root] = getCompletions
                }
            }
        }
        return @{
            completions      = $_completions
            completions_data = $_completions_data
        }
    } -ArgumentList $PSCompletions
}

$PSCompletions.methods['order_job'] = {
    param([string]$history_path, [string]$root, [string]$path_order)
    $PSCompletions.order."$($root)_job" = Start-Job -ScriptBlock {
        param($PScompletions, [string]$path_history, [string]$root, [string]$path_order)

        $order_dir = $PSCompletions.path.order
        if (!(Test-Path $order_dir)) {
            New-Item -ItemType Directory -Path $order_dir -Force | Out-Null
        }

        # XXX 这里不能直接使用 $PSCompletions.input_pattern，实测会导致排序失效
        $input_pattern = [regex]::new("(?:`"[^`"]*`"|'[^']*'|\S)+", [System.Text.RegularExpressions.RegexOptions]::Compiled)

        $index = 0
        $order = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
        $contents = Get-Content $path_history -Encoding utf8 -ErrorAction SilentlyContinue
        foreach ($_ in $contents) {
            $alias = $PSCompletions.data.alias[$root]
            if ($null -eq $alias) {
                $alias = @($root)
            }
            foreach ($a in $alias) {
                if ($_ -match "^[^\S\n]*$a\s+.+") {
                    $_ = $_ -replace '^\w+\s+', ''
                    $input_arr = @()
                    $matches = [regex]::Matches($_, $input_pattern)
                    foreach ($match in $matches) { $input_arr += $match.Value }
                    $index += $input_arr.Count
                    $i = 0
                    foreach ($completion in $input_arr) {
                        $order[$completion] = $index + $i
                        $i--
                    }
                    break
                }
            }
        }

        $index = 0
        $result = [System.Collections.Hashtable]::New([System.StringComparer]::Ordinal)
        $sorted = $order.Keys | Sort-Object { $order[$_] } -CaseSensitive
        foreach ($_ in $sorted) {
            $index++
            $result[$_] = $index
        }

        $old = Get-Content -Raw $path_order -ErrorAction SilentlyContinue | ConvertFrom-Json | ConvertTo-Json -Compress
        $new = $result | ConvertTo-Json -Compress
        if ($new -ne $old) {
            $new | Out-File $path_order -Force -Encoding utf8
        }

        return $result
    } -ArgumentList $PScompletions, $history_path, $root, $path_order
}
