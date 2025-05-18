Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ConvertFrom_JsonToHashtable {
    param([string]$json)
    ConvertFrom-Json $json -AsHashtable
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod start_job {
    # Start-Job 传入的对象的方法会丢失
    # Start-ThreadJob 不会，但是耗时方法执行会卡住主线程

    $PSCompletions.job = Start-ThreadJob -ScriptBlock {
        param($PSCompletions)

        $null = Start-ThreadJob -ScriptBlock {
            param($PSCompletions)

            function get_raw_content {
                param ([string]$path, [bool]$trim = $true)
                $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
                if ($res) {
                    if ($trim) { return $res.Trim() }
                    return $res
                }
                ''
            }
            function replace_content {
                param ($data, $separator = '')
                $data = $data -join $separator
                $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
                $matches = [regex]::Matches($data, $pattern)
                foreach ($match in $matches) {
                    $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
                }
                if ($data -match $pattern) { (replace_content $data) }else { return $data }
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
                        $wc.DownloadFile($url, $file)
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
                        $content = (Invoke-WebRequest -Uri "$url/completions.json").Content | ConvertFrom-Json

                        $remote_list = $content.list

                        $diff = Compare-Object $remote_list $current_list -PassThru
                        if ($diff) {
                            $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8
                            $content | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
                            $PSCompletions.list = $remote_list
                        }
                        else {
                            Clear-Content $PSCompletions.path.change -Force
                            $PSCompletions.list = $current_list
                        }
                        $isErr = $false
                        return $remote_list
                    }
                    catch {}
                }
            }

            $wc = New-Object System.Net.WebClient

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

                $data.alias.$cmd = @()
                if ($PSCompletions.data.alias[$cmd] -ne $null) {
                    foreach ($a in $PSCompletions.data.alias.$cmd) {
                        $data.alias.$cmd += $a
                        $data.aliasMap.$a = $cmd
                    }
                }
                else {
                    $data.alias.$cmd += $cmd
                    $data.aliasMap.$cmd = $cmd
                }

                ## config.comp_config
                $completion = $cmd
                $data.config.comp_config.$completion = [ordered]@{}
                if ($PSCompletions.config.comp_config[$completion]) {
                    foreach ($c in $PSCompletions.config.comp_config.$completion.Keys) {
                        $data.config.comp_config.$completion.$c = $PSCompletions.config.comp_config.$completion.$c
                    }
                }
            }

            ## config
            foreach ($c in $PSCompletions.default_config.Keys) {
                if ($PSCompletions.config[$c] -ne $null) {
                    $data.config.$c = $PSCompletions.config.$c
                }
                else {
                    $data.config.$c = $PSCompletions.default_config.$c
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
                $json = get_raw_content $path | ConvertFrom-Json -AsHashtable
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
                foreach ($r in $data.config.comp_config[$_].Keys.Where({ $_ -notin $config_list })) {
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
            $_keys = @()
            foreach ($k in $data.config.comp_config.Keys) {
                if (!$data.config.comp_config[$k].Count) {
                    $_keys += $k
                }
            }
            foreach ($_ in $_keys) {
                $data.config.comp_config.Remove($_)
            }

            $new_data = $data | ConvertTo-Json -Depth 100 -Compress
            $old_data = get_raw_content $PSCompletions.path.data | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress
            if ($new_data -ne $old_data) {
                $new_data | Out-File $PScompletions.path.data -Force -Encoding utf8
            }

            # check version
            try {
                if ($PSCompletions.config.enable_module_update -eq 1) {
                    $urls = $PSCompletions.urls + "https://pscompletions.abgox.com"
                    foreach ($url in $urls) {
                        try {
                            $newVersion = (Invoke-WebRequest -Uri "$url/module/version.json" | ConvertFrom-Json).version
                            break
                        }
                        catch {}
                    }
                    $newVersion = $newVersion -replace 'v', ''
                    if ($newVersion -match "^[\d\.]+$") {
                        $versions = @($PSCompletions.version, $newVersion) | Sort-Object { [Version] $_ }
                        if ($versions[-1] -ne $PSCompletions.version) {
                            $data = get_raw_content $PSCompletions.path.data | ConvertFrom-Json -AsHashtable
                            $data.config.enable_module_update = $versions[-1]
                            $data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
                        }
                    }
                }
            }
            catch {}

            # check update
            if (!(Test-Path $PSCompletions.path.update)) {
                New-Item $PSCompletions.path.update -Force -ErrorAction SilentlyContinue
            }
            if ($PSCompletions.config.enable_completions_update -eq 1) {
                $update_list = @()
                foreach ($_ in (Get-ChildItem $PSCompletions.path.completions -ErrorAction SilentlyContinue).Where({ $_.Name -in $PSCompletions.list })) {
                    $isErr = $true
                    foreach ($url in $PSCompletions.urls) {
                        try {
                            $response = Invoke-WebRequest -Uri "$url/completions/$($_.Name)/guid.txt"
                            $isErr = $false
                            break
                        }
                        catch {}
                    }
                    if ($isErr) {
                        continue
                    }
                    try {
                        $content = $response.Content.Trim()
                        $guid = get_raw_content "$($PSCompletions.path.completions)/$($_.Name)/guid.txt"
                        if ($guid -ne $content -and $content -match "^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$") {
                            $update_list += $_.Name
                        }
                    }
                    catch {}
                }
                if ($update_list) { $update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8 }
                else { Clear-Content $PSCompletions.path.update -Force }
            }
        } -ArgumentList $PSCompletions

        $wc = New-Object System.Net.WebClient
        function get_raw_content {
            param ([string]$path, [bool]$trim = $true)
            $res = Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue
            if ($res) {
                if ($trim) { return $res.Trim() }
                return $res
            }
            ''
        }
        function replace_content {
            param ($data, $separator = '')
            $data = $data -join $separator
            $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
            $matches = [regex]::Matches($data, $pattern)
            foreach ($match in $matches) {
                $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
            }
            if ($data -match $pattern) { (replace_content $data) }else { return $data }
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
                    $wc.DownloadFile($url, $file)
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
        function getCompletions {
            $guid = $PSCompletions.guid
            $obj = @{}
            $special_options = @{
                WriteSpaceTab              = @()
                WriteSpaceTab_and_SpaceTab = @()
            }
            function parseJson($cmds, $obj, $cmdO, [switch]$isOption) {
                if ($obj[$cmdO].$guid -eq $null) {
                    $obj[$cmdO] = @{
                        $guid = @()
                    }
                }
                foreach ($cmd in $cmds) {
                    $symbols = @()
                    if ($isOption) {
                        if ($cmd.next -eq $null -and $cmd.options -eq $null) {
                            $symbols += 'OptionTab'
                        }
                        else {
                            $symbols += 'WriteSpaceTab'
                            if ($cmd.next -is [array] -or $cmd.options -is [array]) {
                                $symbols += 'SpaceTab'
                            }
                        }
                    }
                    else {
                        if ($cmd.next -is [array] -or $cmd.options -is [array]) {
                            $symbols += 'SpaceTab'
                        }
                    }
                    if ($cmd.name -eq $null) {
                        continue
                    }

                    $alias_list = $cmd.alias + $cmd.name

                    $obj.$cmdO.$guid += @{
                        CompletionText = $cmd.name
                        ListItemText   = $cmd.name
                        ToolTip        = $cmd.tip
                        symbols        = $symbols
                        alias          = $alias_list
                    }

                    foreach ($alias in $cmd.alias) {
                        $obj.$cmdO.$guid += @{
                            CompletionText = $alias
                            ListItemText   = $alias
                            ToolTip        = $cmd.tip
                            symbols        = $symbols
                            alias          = $alias_list
                        }
                    }

                    if ($symbols) {
                        if ('WriteSpaceTab' -in $symbols) {
                            $pad = if ($cmdO -in @('rootOptions', 'commonOptions')) { ' ' }else { $cmdO + ' ' }
                            $special_options.WriteSpaceTab += $pad + $cmd.name
                            if ($cmd.alias) {
                                foreach ($a in $cmd.alias) { $special_options.WriteSpaceTab += $pad + $a }
                            }
                            if ('SpaceTab' -in $symbols) {
                                $special_options.WriteSpaceTab_and_SpaceTab += $pad + $cmd.name
                                if ($cmd.alias) {
                                    foreach ($a in $cmd.alias) { $special_options.WriteSpaceTab_and_SpaceTab += $pad + $a }
                                }
                            }
                        }
                    }
                    if ($cmd.options) {
                        parseJson $cmd.options $obj.$cmdO "$($cmd.name)" -isOption
                        foreach ($alias in $cmd.alias) {
                            parseJson $cmd.options $obj.$cmdO "$($alias)" -isOption
                        }
                    }
                    if ($cmd.next -or 'WriteSpaceTab' -in $symbols) {
                        parseJson $cmd.next $obj.$cmdO "$($cmd.name)"
                        foreach ($alias in $cmd.alias) {
                            parseJson $cmd.next $obj.$cmdO "$($alias)"
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
            $_completions_data."$($root)_common_options" = $obj.commonOptions.$guid | ForEach-Object { $_.CompletionText }
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
            if ($PSCompletions.config.comp_config[$completion].language) {
                $config_language = $PSCompletions.config.comp_config.$completion.language
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

        # XXX: 如果存在大量补全，考虑使用 runspace, 参考 $PSCompletions.handle_data_by_runspace
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
                    $_completions.$root = get_raw_content $path_language | ConvertFrom-Json -AsHashtable
                    $_completions_data.$root = getCompletions
                }
            }
        }
        return @{
            completions      = $_completions
            completions_data = $_completions_data
        }
    } -ArgumentList $PSCompletions
}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod order_job {
    param([string]$history_path, [string]$root, [string]$path_order)
    $PSCompletions.order."$($root)_job" = Start-ThreadJob -ScriptBlock {
        param($PScompletions, [string]$path_history, [string]$root, [string]$path_order)

        $order_dir = $PSCompletions.path.order
        if (!(Test-Path $order_dir)) {
            New-Item -ItemType Directory -Path $order_dir -Force | Out-Null
        }

        $order = [ordered]@{}
        $index = 0
        foreach ($_ in Get-Content $path_history -Encoding utf8 -ErrorAction SilentlyContinue) {
            $alias = $PSCompletions.data.alias.$root
            if (!$alias) {
                $alias = @($root)
            }
            foreach ($a in $alias) {
                if ($_ -match "^[^\S\n]*$a\s+.+") {
                    $_ = $_ -replace '^\w+\s+', ''
                    $input_arr = @()
                    $matches = [regex]::Matches($_, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                    foreach ($match in $matches) { $input_arr += $match.Value }
                    $index += $input_arr.Count
                    $i = 0
                    foreach ($completion in $input_arr) {
                        $order.$completion = $index + $i
                        $i--
                    }
                    break
                }
            }
        }

        $index = 0
        $result = [ordered]@{}
        $sorted = $order.Keys | Sort-Object { $order.$_ } -CaseSensitive
        foreach ($_ in $sorted) {
            $index++
            $result.$_ = $index
        }

        $old = Get-Content -Raw $path_order -ErrorAction SilentlyContinue | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress
        $new = $result | ConvertTo-Json -Depth 100 -Compress
        if ($new -ne $old) {
            $new | Out-File $path_order -Force -Encoding utf8
        }

        return $result
    } -ArgumentList $PScompletions, $history_path, $root, $path_order
}
