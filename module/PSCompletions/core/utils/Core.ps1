﻿Add-Member -InputObject $PSCompletions -MemberType ScriptMethod ConvertFrom_JsonToHashtable {
    param([string]$json)
    ConvertFrom-Json -AsHashtable $json
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod start_job {
    $PSCompletions.job = Start-ThreadJob -ScriptBlock {
        param($PSCompletions)

        $null = Start-ThreadJob -ScriptBlock {
            param($PSCompletions)
            $PSCompletions.wc = New-Object System.Net.WebClient
            function get_content {
                param ([string]$path)
                $res = (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue).Where({ $_ -ne '' })
                if ($res) { return $res }
                , @()
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
            function download_list {
                if (!(Test-Path $PScompletions.path.completions_json)) {
                    @{ list = @('psc') } | ConvertTo-Json -Compress | Out-File $PScompletions.path.completions_json -Encoding utf8 -Force
                }
                $current_list = (get_raw_content $PScompletions.path.completions_json | ConvertFrom-Json).list
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
            function ensure_dir {
                param([string]$path)
                if (!(Test-Path $path)) { New-Item -ItemType Directory $path > $null }
            }
            function ensure_psc {
                $url = "$($PSCompletions.url)/completions/psc"
                $language = if ($PSCompletions.language -eq 'zh-CN') { 'zh-CN' }else { 'en-US' }

                ensure_dir "$($PSCompletions.path.completions)/psc"
                ensure_dir "$($PSCompletions.path.completions)/psc/language"

                $path_list = @(
                    "psc/language/$language.json",
                    "psc/config.json",
                    "psc/guid.txt",
                    "psc/hooks.ps1"
                )
                foreach ($path in $path_list) {
                    $path_file = "$($PSCompletions.path.completions)/$path"
                    if (!(Test-Path $path_file)) {
                        $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/completions/$path", $path_file)
                    }
                }
            }

            ensure_psc
            download_list

            # data.json
            $data = [ordered]@{
                list     = @()
                alias    = [ordered]@{}
                aliasMap = [ordered]@{}
                config   = [ordered]@{}
            }
            foreach ($f in Get-ChildItem $PSCompletions.path.completions -Directory) {
                $data.list += $f.Name
            }
            foreach ($_ in $data.list) {
                $data.alias.$_ = @()
                if ($PSCompletions.data.alias.$_) {
                    foreach ($a in $PSCompletions.data.alias.$_) {
                        $data.alias.$_ += $a
                        $data.aliasMap.$a = $_
                    }
                }
                else {
                    $data.alias.$_ += $_
                    $data.aliasMap.$_ = $_
                }
            }

            ## config
            foreach ($c in $PSCompletions.default_config.Keys) {
                if ($PSCompletions.config.$c) {
                    $data.config.$c = $PSCompletions.config.$c
                }
                else {
                    $data.config.$c = $PSCompletions.default_config.$c
                }
            }

            ## config.comp_config
            $data.config.comp_config = [ordered]@{}
            foreach ($_ in Get-ChildItem $PSCompletions.path.completions -Directory) {
                $completion = $_.Name
                if (!$data.config.comp_config.$completion) {
                    $data.config.comp_config.$completion = [ordered]@{}
                }
                foreach ($c in $PSCompletions.config.comp_config.$completion.Keys) {
                    $data.config.comp_config.$completion.$c = $PSCompletions.config.comp_config.$completion.$c
                }
            }
            foreach ($_ in $PSCompletions.data.list) {
                $path = "$($PSCompletions.path.completions)/$_/config.json"
                if (!(Test-Path $path)) {
                    $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/completions/$_/config.json", $path)
                }
                $json = get_raw_content $path | ConvertFrom-Json
                $path = "$($PSCompletions.path.completions)/$_/language/$($json.language[0]).json"
                $json = get_raw_content $path | ConvertFrom-Json -AsHashtable
                foreach ($item in $json.config) {
                    if (!$data.config.comp_config.$_) {
                        $data.config.comp_config.$_ = [ordered]@{}
                    }
                    if ($data.config.comp_config.$_.$($item.name) -in @('', $null)) {
                        $data.config.comp_config.$_.$($item.name) = $item.value
                    }
                }
            }
            $_keys = @()
            foreach ($k in $data.config.comp_config.Keys) {
                if (!$data.config.comp_config.$k.Count) {
                    $_keys += $k
                }
            }
            foreach ($_ in $_keys) {
                $data.config.comp_config.Remove($_)
            }

            $new_data = $data | ConvertTo-Json -Depth 100 -Compress
            $old_data = $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress
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
                        $PSCompletions.config.enable_module_update = $versions[-1]
                        $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
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
        } -ArgumentList $PSCompletions

        $PSCompletions.wc = New-Object System.Net.WebClient
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

        $completion_datas = @{}
        $time = (Get-Date).AddMonths(-6)
        $filter = (Get-ChildItem $PSCompletions.path.completions -Filter 'order.json' -File -Recurse).Where({ $_.LastWriteTime -gt $time })
        foreach ($_ in $filter) {
            $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
            if ($cmd -in $PSCompletions.data.list) {
                $language = get_language $cmd
                $path_language = "$($PSCompletions.path.completions)/$cmd/language/$language.json"
                if (Test-Path $path_language) {
                    $completion_datas.$cmd = (get_raw_content $path_language) | ConvertFrom-Json -AsHashtable
                }
                else {
                    try {
                        $PSCompletions.wc.DownloadFile("$($PSCompletions.url)/completions/$cmd/language/$language.json", $path_language)
                        $completion_datas.$cmd = (get_raw_content $path_language) | ConvertFrom-Json -AsHashtable
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
    $PSCompletions.order."$($root)_job" = Start-ThreadJob -ScriptBlock {
        param($PScompletions, $completions, [string]$path_history, [string]$root, [string]$path_order)
        $order = [ordered]@{}
        $index = 1
        foreach ($_ in $completions) {
            $order.$($_.name -join ' ') = $index
            $index++
        }
        $historys = @()
        foreach ($_ in Get-Content $path_history -Encoding utf8 -ErrorAction SilentlyContinue) {
            foreach ($alias in $PSCompletions.data.alias.$root) {
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
