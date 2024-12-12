Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ConvertFrom_JsonToHashtable {
    param([string]$json)
    # Handle json string
    $matches = [regex]::Matches($json, '\s*"\s*"\s*:')
    foreach ($match in $matches) {
        $json = $json -replace $match.Value, "`"empty_key_$([System.Guid]::NewGuid().Guid)`":"
    }
    $json = [regex]::Replace($json, ",`n?(\s*`n)?\}", "}")
    function ConvertToHashtable {
        param($obj)
        $hash = @{}
        if ($obj -is [System.Management.Automation.PSCustomObject]) {
            foreach ($_ in $obj | Get-Member -MemberType Properties) {
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
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod start_job {
    $PSCompletions.job = Start-Job -ScriptBlock {
        param($PSCompletions)
        $wc = New-Object System.Net.WebClient
        function ConvertFrom_JsonToHashtable {
            param(
                [Parameter(ValueFromPipeline = $true)]
                [string]$json
            )
            # Handle json string
            $matches = [regex]::Matches($json, '\s*"\s*"\s*:')
            foreach ($match in $matches) {
                $json = $json -replace $match.Value, "`"empty_key_$([System.Guid]::NewGuid().Guid)`":"
            }
            $json = [regex]::Replace($json, ",`n?(\s*`n)?\}", "}")
            function ConvertToHashtable {
                param($obj)
                $hash = @{}
                if ($obj -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($_ in $obj | Get-Member -MemberType Properties) {
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
        function ensure_dir {
            param([string]$path)
            if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
        }
        function ensure_psc {
            $url = "$($PSCompletions.url)/completions/psc"
            # XXX: language
            # $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }

            ensure_dir "$($PSCompletions.path.completions)/psc"
            ensure_dir "$($PSCompletions.path.completions)/psc/language"

            $path_list = @(
                # "psc/language/$language.json",
                "psc/language/zh-CN.json",
                "psc/language/en-US.json",
                "psc/config.json",
                "psc/guid.txt",
                "psc/hooks.ps1"
            )
            foreach ($path in $path_list) {
                $path_file = "$($PSCompletions.path.completions)/$path"
                if (!(Test-Path $path_file)) {
                    $wc.DownloadFile("$($PSCompletions.url)/completions/$path", $path_file)
                }
            }
        }
        function download_list {
            ensure_dir $PSCompletions.path.temp
            if (!(Test-Path $PSCompletions.path.completions_json)) {
                @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
            }
            $current_list = (get_raw_content $PSCompletions.path.completions_json | ConvertFrom-Json).list
            try {
                $content = (Invoke-WebRequest -Uri "$($PSCompletions.url)/completions.json").Content | ConvertFrom-Json

                $remote_list = $content.list

                $diff = Compare-Object $remote_list $current_list -PassThru
                if ($diff) {
                    if ($PSCompletions.is_update_init) {
                        $diff = ''
                    }
                    $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8
                    $content | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
                }
                else {
                    Clear-Content $PSCompletions.path.change -Force
                }
            }
            catch {}
        }

        ensure_dir "$($PSCompletions.path.temp)/order"

        ensure_psc

        $null = download_list

        # data.json
        $data = [ordered]@{
            list     = @()
            alias    = [ordered]@{}
            aliasMap = [ordered]@{}
            config   = [ordered]@{}
        }
        $data.config.comp_config = [ordered]@{}
        foreach ($_ in Get-ChildItem $PSCompletions.path.completions -Directory) {
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
            if ($data.config.comp_config[$completion] -eq $null) {
                $data.config.comp_config.$completion = [ordered]@{}
            }
            foreach ($c in $PSCompletions.config.comp_config.$completion.Keys) {
                $data.config.comp_config.$completion.$c = $PSCompletions.config.comp_config.$completion.$c
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
            $path = "$($PSCompletions.path.completions)/$_/config.json"
            if (!(Test-Path $path)) {
                $wc.DownloadFile("$($PSCompletions.url)/completions/$_/config.json", $path)
            }
            $json = get_raw_content $path | ConvertFrom-Json
            $path = "$($PSCompletions.path.completions)/$_/language/$($json.language[0]).json"
            $json = get_raw_content $path | ConvertFrom_JsonToHashtable
            $config_list = $PSCompletions.default_completion_item
            foreach ($item in $config_list) {
                if ($data.config.comp_config[$_].$($item.name) -eq '') {
                    $data.config.comp_config[$_].Remove($item.name)
                }
            }
            foreach ($item in $json.config) {
                $config_list += $item.name
                if ($data.config.comp_config[$_] -eq $null) {
                    $data.config.comp_config[$_] = [ordered]@{}
                }
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
                $data.config.comp_config[$_].Remove($r)
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
                $response = Invoke-WebRequest -Uri "$($PSCompletions.url)/module/version.txt"
                $content = $response.Content.Trim()
                $versions = @($PSCompletions.version, $content) | Sort-Object { [Version] $_ }
                if ($versions[-1] -ne $PSCompletions.version) {
                    $data = get_raw_content $PSCompletions.path.data | ConvertFrom_JsonToHashtable
                    $data.config.enable_module_update = $versions[-1]
                    $data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
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
                try {
                    $response = Invoke-WebRequest -Uri "$($PSCompletions.url)/completions/$($_.Name)/guid.txt"
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

        function getCompletions {
            $guid = $PSCompletions.guid
            $obj = @{}
            $special_options = @{
                WriteSpaceTab              = @()
                WriteSpaceTab_and_SpaceTab = @()
            }
            function parseJson($cmds, $obj, $cmdO, [switch]$isOption) {
                $obj.$cmdO = @{
                    $guid = @()
                }
                foreach ($cmd in $cmds) {
                    $symbols = @()
                    if ($isOption) {
                        $symbols += 'OptionTab'
                    }
                    if ($cmd.next -is [array] -or $cmd.options -is [array]) {
                        if ($isOption) {
                            $symbols += 'WriteSpaceTab'
                        }
                        if ($cmd.next.Count -or $cmd.options.Count) {
                            $symbols += 'SpaceTab'
                        }
                    }
                    if ($cmd.symbol) {
                        $symbols += (replace_content $cmd.symbol ' ') -split ' '
                        $symbols = $symbols | Select-Object -Unique
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
                try {
                    $wc.DownloadFile("$($PSCompletions.url)/completions/$completion/config.json", $path_config)
                }
                catch {}
                $content_config = get_raw_content $path_config | ConvertFrom-Json
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

        $_completions = @{}
        $_completions_data = @{}
        $time = (Get-Date).AddMonths(-6)
        $filter = (Get-ChildItem $PSCompletions.path.completions -Filter 'order.json' -File -Recurse).Where({ $_.LastWriteTime -gt $time })
        foreach ($_ in $filter) {
            $root = Split-Path (Split-Path $_.FullName -Parent) -Leaf
            if ($root -in $PSCompletions.data.list) {
                $language = get_language $root
                $path_language = "$($PSCompletions.path.completions)/$root/language/$language.json"
                if (Test-Path $path_language) {
                    $_completions.$root = get_raw_content $path_language | ConvertFrom_JsonToHashtable
                    $_completions_data.$root = getCompletions
                }
                else {
                    try {
                        $wc.DownloadFile("$($PSCompletions.url)/completions/$root/language/$language.json", $path_language)
                        $_completions.$root = get_raw_content $path_language | ConvertFrom_JsonToHashtable
                        $_completions_data.$root = getCompletions
                    }
                    catch {}
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
    $PSCompletions.order."$($root)_job" = Start-Job -ScriptBlock {
        param($PScompletions, [string]$path_history, [string]$root, [string]$path_order)

        $order_dir = "$($PScompletions.path.temp)/order"
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
        $result | ConvertTo-Json -Depth 100 -Compress | Out-File $path_order -Force -Encoding utf8
        return $result
    } -ArgumentList $PScompletions, $history_path, $root, $path_order
}
