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
        $PSCompletions.wc = New-Object System.Net.WebClient
        function convert_from_json_to_hashtable {
            param(
                [Parameter(ValueFromPipeline = $true)]
                [string]$json
            )
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
            return ''
        }
        function get_language {
            param ([string]$completion)
            $path_config = "$($PSCompletions.path.completions)/$completion/config.json"
            if (!(Test-Path $path_config) -or !( get_raw_content $path_config)) {
                try {
                    $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/completions/$completion/config.json", $path_config)
                }
                catch {}
            }
            $content_config = (get_raw_content $path_config) | ConvertFrom-Json
            if ($PSCompletions.config.comp_config.$completion -and $PSCompletions.config.comp_config.$completion.language) {
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
            return $language
        }
        function set_config {
            param ([string]$k, [string]$v)
            $c = get_raw_content $PScompletions.path.config | convert_from_json_to_hashtable
            $c.$k = $v
            $c | ConvertTo-Json -Depth 100 -Compress | Out-File $PScompletions.path.config -Encoding utf8 -Force
        }
        function download_list {
            if (!(Test-Path $PScompletions.path.completions_json)) {
                @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PScompletions.path.completions_json -Encoding utf8 -Force
            }
            $current_list = (get_raw_content $PScompletions.path.completions_json | ConvertFrom-Json).list
            if ($PScompletions.url) {
                try {
                    $content = (Invoke-WebRequest -Uri "$($PScompletions.url)/completions.json").Content | ConvertFrom-Json
                    $remote_list = $content.list

                    $diff = Compare-Object $remote_list $current_list -PassThru
                    if ($diff) {
                        $diff | Out-File $PScompletions.path.change -Force -Encoding utf8
                        $content | ConvertTo-Json -Depth 100 -Compress | Out-File $PScompletions.path.completions_json -Encoding utf8 -Force
                    }
                    else {
                        Clear-Content $PScompletions.path.change -Force
                    }
                }
                catch {}
            }
        }

        download_list

        # ensure completion config
        foreach ($_ in $PSCompletions.cmd.Keys) {
            $path = "$($PSCompletions.path.completions)/$_/config.json"
            $json = get_raw_content $path | ConvertFrom-Json
            $path = "$($PSCompletions.path.completions)/$_/language/$($json.language[0]).json"
            $json = get_raw_content $path | convert_from_json_to_hashtable
            foreach ($item in $json.config) {
                if ($PSCompletions.config.comp_config.$_.$($item.name) -in @('', $null)) {
                    $PSCompletions.config.comp_config.$_.$($item.name) = $item.value
                    $need_update_config = $true
                }
            }
        }
        if ($need_update_config) { $PSCompletions.config | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.config -Encoding utf8 -Force }

        # check version
        try {
            if ($PSCompletions.config.module_update -eq 1) {
                $response = Invoke-WebRequest -Uri "$($PSCompletions.url)/module/version.txt"
                $content = $response.Content.Trim()
                $versions = @($PSCompletions.version, $content) | Sort-Object { [Version] $_ }
                if ($versions[-1] -ne $PSCompletions.version) {
                    set_config 'module_update' $versions[-1]
                }
            }
        }
        catch {}

        # check update
        if ($PSCompletions.config.update -eq 1) {
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

        $completion_datas = @{}
        $time = (Get-Date).AddMonths(-6)
        $filter = (Get-ChildItem $PSCompletions.path.completions -Filter "order.json" -File -Recurse).Where({ $_.LastWriteTime -gt $time })
        foreach ($_ in $filter) {
            $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
            if ($cmd -in $PSCompletions.cmd.Keys) {
                $language = get_language $cmd
                $path_language = "$($PSCompletions.path.completions)/$cmd/language/$language.json"
                if (Test-Path $path_language) {
                    $completion_datas.$cmd = (get_raw_content $path_language) | convert_from_json_to_hashtable
                }
                else {
                    try {
                        $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/completions/$cmd/language/$language.json", $path_language)
                        $completion_datas.$cmd = (get_raw_content $path_language) | convert_from_json_to_hashtable
                    }
                    catch {}
                }
            }
        }
        return $completion_datas
    } -ArgumentList $PSCompletions
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod order_job {
    param($completions, [string]$history_path, [string]$root, [string]$path_order)
    $PSCompletions.order."$($root)_job" = Start-Job -ScriptBlock {
        param($PScompletions, $completions, [string]$path_history, [string]$root, [string]$path_order)
        $order = [ordered]@{}
        $index = 1
        foreach ($_ in $completions) {
            $order.$($_.name -join ' ') = $index
            $index++
        }
        $historys = @()
        foreach ($_ in Get-Content $path_history -Encoding utf8 -ErrorAction SilentlyContinue) {
            foreach ($alias in $PSCompletions.cmd.$root) {
                if ($_ -match "^[^\S\n]*$alias\s+.+") {
                    $historys += $_
                    break
                }
            }
        }
        $index = -1
        function handle_order {
            param([array]$history)
            $str = $history -join ' '
            if ($str -in $order.Keys) {
                $order.$str = $index
            }
            if ($history.Count -eq 1) {
                return
            }
            else {
                handle_order $history[0..($history.Count - 2)]
            }
        }
        foreach ($_ in $historys) {
            $matches = [regex]::Matches($_, "(?:`"[^`"]*`"|'[^']*'|\S)+")
            $cmd = @()
            foreach ($m in $matches) { $cmd += $m.Value }
            if ($cmd.Count -gt 1) {
                handle_order $cmd[1..($cmd.Count - 1)]
                $index--
            }
        }
        $json = $order | ConvertTo-Json -Depth 100 -Compress
        $matches = [regex]::Matches($json, '\s*"\s*"\s*:')
        foreach ($match in $matches) {
            $json = $json -replace $match.Value, "`"empty_key_$([System.Guid]::NewGuid().Guid)`":"
        }
        $json | Out-File $path_order -Encoding utf8 -Force
        return $order
    } -ArgumentList $PScompletions, $completions, $history_path, $root, $path_order
}
