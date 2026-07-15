function PSCompletions {
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

    $arg = $args

    Set-Alias Write-Host Microsoft.PowerShell.Utility\Write-Host -ErrorAction Ignore
    Set-Alias Write-Output Microsoft.PowerShell.Utility\Write-Output -ErrorAction Ignore

    function _replace {
        param ($data, $separator = '')
        $data = $data -join $separator
        if ($data -notlike '*{{*') { return $data }
        $matches = [regex]::Matches($data, $PSCompletions.replace_pattern)
        foreach ($match in $matches) {
            $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
        }
        if ($data -match $PSCompletions.replace_pattern) { (_replace $data) }else { return $data }
    }
    function download_list {
        $PSCompletions.ensure_dir($PSCompletions.path.temp)
        if (!(Test-Path $PSCompletions.path.completions_json)) {
            @{ update = @{ psc = '' }; meta = @{} } | ConvertTo-Json -Compress | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force
        }
        $current_json = $PSCompletions.get_raw_content($PSCompletions.path.completions_json) | ConvertFrom-Json
        $current_list = @($current_json.update.PSObject.Properties.Name)
        if ($null -eq $current_list) { $current_list = @() }

        $params = @{ ErrorAction = 'Stop' }
        if ($PSEdition -eq 'Core') { $params['OperationTimeoutSeconds'] = 30 }else { $params['TimeoutSec'] = 30 }

        $isErr = $true
        $errMsg = @()
        foreach ($url in $PSCompletions.urls) {
            $params['Uri'] = "$url/completions.json"
            try {
                $response = Invoke-RestMethod @params
            }
            catch {
                $errMsg += $_.Exception.Message
                continue
            }
            $remote_list = @($response.update.PSObject.Properties.Name)
            try {
                $diff = Compare-Object $remote_list $current_list -PassThru
                if ($diff) {
                    $diff | Out-File $PSCompletions.path.change -Force -Encoding utf8 -ErrorAction Stop
                }
                else {
                    Clear-Content $PSCompletions.path.change -Force -ErrorAction Ignore
                }
                $PSCompletions.list = $remote_list
                $new = $response | ConvertTo-Json -Compress -Depth 10
                $old = Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10
                if ($new -ne $old) {
                    $new | Out-File $PSCompletions.path.completions_json -Encoding utf8 -Force -ErrorAction Stop
                }
                $isErr = $false
                return $remote_list
            }
            catch {
                Write-Host $_.Exception.Message -ForegroundColor Red
                return $false
            }
        }
        if ($isErr) {
            $errMsg | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            return $false
        }
    }
    function Show-ParamError {
        param($flag, $cmd, $err_info = $PSCompletions.info.$cmd.err.$flag, $example = $PSCompletions.info.$cmd.example)

        $err = if ($flag -eq 'min') { $PSCompletions.info.param_min }
        elseif ($flag -eq 'max') { $PSCompletions.info.param_max }
        else { $PSCompletions.info.param_err }
        $PSCompletions.write_with_color((_replace $err))

        if ($err_info) {
            $PSCompletions.write_with_color((_replace $err_info))
        }
        if ($example) {
            $PSCompletions.write_with_color('<@Cyan>' + (_replace $example))
        }
    }
    function Show-List {
        $max_len = ($PSCompletions.data.list | Measure-Object -Maximum Length).Maximum
        $max_len = [Math]::Max($max_len, 10)
        foreach ($_ in $PSCompletions.data.list) {
            $alias = $PSCompletions.data.alias.$_ -join ' '
            $data.Add([PSCustomObject]@{
                    Completion = $_
                    Alias      = $alias
                })
        }
        $data
    }
    function Out-Data {
        if ($PSCompletions.need_update_data) {
            foreach ($_ in $PSCompletions.data.list) {
                if (-not $PSCompletions.config.completion[$_].Count) {
                    $null = $PSCompletions.config.completion.Remove($_)
                }
            }
            $saveData = [ordered]@{}
            foreach ($key in $PSCompletions.data.Keys) {
                if ($key -notin 'list', 'aliasMap') {
                    $saveData[$key] = $PSCompletions.data[$key]
                }
            }
            $saveData | ConvertTo-Json -Depth 10 | Out-File $PSCompletions.path.data -Force -Encoding utf8
            $PSCompletions.need_update_data = $null
        }
    }
    function _list {
        $data = [System.Collections.Generic.List[System.Object]]@()
        if ($arg[1] -eq '--remote') {
            if (!(download_list)) {
                return
            }
            $max_len = ($PSCompletions.list | Measure-Object -Maximum Length).Maximum
            foreach ($_ in $PSCompletions.list) {
                $status = if ($PSCompletions.data.alias[$_]) { $PSCompletions.info.list.added }else { $null }
                $data.Add([PSCustomObject]@{
                        Completion = $_
                        Status     = $status
                    })
            }
            $data
        }
        else {
            Show-List
        }
    }
    function _add {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'add'
            return
        }
        if (!(download_list)) {
            return
        }
        if ($arg | Where-Object { $_ -eq '--all' }) {
            foreach ($_ in $PSCompletions.list) {
                $PSCompletions.add_completion($_)
                $PSCompletions.need_update_data = $true
            }
            if (!$PSCompletions.use_module_completion_menu) {
                $PSCompletions.handle_completion()
            }
            return
        }
        $completions_list = $arg[1..($arg.Length - 1)]
        foreach ($completion in $completions_list) {
            if ($completion -in $PSCompletions.list) {
                $PSCompletions.add_completion($completion)
                $PSCompletions.need_update_data = $true
            }
            else {
                $PSCompletions.write_with_color((_replace $PSCompletions.info.add.err.no))
            }
        }
        if (!$PSCompletions.use_module_completion_menu) {
            $PSCompletions.handle_completion()
        }
    }
    function _rm {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'rm'
            return
        }
        Clear-Content $PSCompletions.path.update -Force -ErrorAction Ignore
        $PSCompletions.update = @()

        $data = [ordered]@{
            alias  = [ordered]@{}
            config = $PSCompletions.data.config
        }
        if ($arg | Where-Object { $_ -eq '--all' }) {
            foreach ($completion in $PSCompletions.data.list) {
                $dir = Join-Path $PSCompletions.path.completions $completion
                Remove-Item $dir -Recurse -Force -ErrorAction Ignore
                if (!(Test-Path $dir)) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.rm.done))
                }
            }
            $data.config.completion = [ordered]@{}
        }
        else {
            $remove_list = @()
            foreach ($completion in $arg[1..($arg.Length - 1)]) {
                $dir = Join-Path $PSCompletions.path.completions $completion
                $exist = Test-Path $dir
                if ($completion -in $PSCompletions.data.list -or $exist) {
                    $remove_list += $completion
                    if (!$exist) {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
                        continue
                    }
                    Remove-Item $dir -Recurse -Force -ErrorAction Ignore
                    if (!(Test-Path $dir)) {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.rm.done))
                    }
                }
                else { $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion)) }
            }
            foreach ($completion in $PSCompletions.data.list.Where({ $_ -notin $remove_list })) {
                $data.alias."$completion" = @()
                if ($PSCompletions.data.alias[$completion]) {
                    foreach ($a in $PSCompletions.data.alias[$completion]) {
                        $data.alias."$completion" += $a
                    }
                }
                else {
                    $data.alias."$completion" += $completion
                }
            }
        }
        $remove = @()
        foreach ($_ in $data.config.completion.keys) {
            if ($_ -notin $data.alias.Keys) {
                $remove += $_
            }
        }
        foreach ($_ in $remove) {
            $null = $data.config.completion.Remove($_)
        }
        $PSCompletions.data.list = @($data.alias.Keys)
        $PSCompletions.data.aliasMap = [ordered]@{}
        foreach ($key in $PSCompletions.data.list) {
            foreach ($a in $data.alias[$key]) {
                $PSCompletions.data.aliasMap[$a] = $key
            }
        }
        $data | ConvertTo-Json -Depth 10 | Out-File $PScompletions.path.data -Force -Encoding utf8
        $PSCompletions.data = $data
    }
    function _update {
        $completion_list = $PSCompletions.data.list.Where({ $_ -in $PSCompletions.list })
        $params = @{
            ErrorAction = 'Stop'
        }
        if ($PSEdition -eq 'Core') {
            $params['OperationTimeoutSeconds'] = 30
        }
        else {
            $params['TimeoutSec'] = 30
        }

        if ($arg.Length -lt 2) {
            # 如果只是使用 psc update 则检查更新
            if (!(download_list)) {
                return
            }
            $update = (Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json).update
            $need_update_list = [System.Collections.Generic.List[string]]@()
            foreach ($completion in $completion_list) {
                if (-not $update.$completion) {
                    continue
                }
                $completion_dir = $PSCompletions.path.completions + "/$completion"
                if (-not (Test-Path $completion_dir) -or (Get-Item $completion_dir).LinkType) {
                    continue
                }
                $p = "$completion_dir/.update"
                if (-not (Test-Path $p)) {
                    $need_update_list += $completion
                    Remove-Item "$($PSCompletions.path.completions)/$completion/guid.json" -Force -ErrorAction Ignore
                    continue
                }
                $content = Get-Content $p -Raw -Encoding utf8 -ErrorAction Ignore
                if ($content -and $content.Trim() -eq $update.$completion) {
                    continue
                }
                $need_update_list += $completion
            }
            $PSCompletions.update = $need_update_list
        }
        else {
            $updated_list = [System.Collections.Generic.List[string]]@()
            $all = $false
            $force = $false
            $arg = $arg | ForEach-Object {
                if ($_ -eq '--all') { $all = $true }
                elseif ($_ -eq '--force') { $force = $true }
                else { $_ }
            }
            if ($all) {
                if ($force) {
                    foreach ($_ in $completion_list) {
                        $PSCompletions.add_completion($_)
                        $updated_list.Add($_)
                    }
                }
                else {
                    foreach ($_ in $PSCompletions.update) {
                        $PSCompletions.add_completion($_)
                        $PSCompletions.need_update_data = $true
                        $updated_list.Add($_)
                    }
                }
            }
            else {
                foreach ($completion in $arg[1..($arg.Length - 1)]) {
                    if ($completion -in $completion_list) {
                        $PSCompletions.add_completion($completion)
                        $PSCompletions.need_update_data = $true
                        $updated_list.Add($completion)
                    }
                    else {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
                    }
                }
            }
            $updated_list = $updated_list.Where({ Test-Path "$($PSCompletions.path.completions)/$_/config.json" })
            if ($updated_list) {
                $PSCompletions.update = $PSCompletions.update.Where({ $_ -notin $updated_list })
            }
            else {
                $PSCompletions.need_update_data = $false
            }
        }
        if ($PSCompletions.update) {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.update_has))
        }
        else {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.update_no))
        }
        $PSCompletions.update | Out-File $PSCompletions.path.update -Force -Encoding utf8
    }
    function _info {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'info'
            return
        }
        $info = Get-Content $PSCompletions.path.completions_json -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json
        $lang = $PSCompletions.config.language
        foreach ($completion in $arg[1..($arg.Length - 1)]) {
            $out = [ordered]@{
                Name = $completion
            }
            $alias = $PSCompletions.data.alias[$completion]
            if ($alias) {
                $out.Alias = $alias
            }
            if ($info.meta.$completion) {
                $meta = $info.meta.$completion.$lang
                if (!$meta) { $meta = $info.meta.$completion.'en-US' }
                if ($meta) {
                    $out.Url = $meta.url
                    $out.Description = $meta.description
                }
            }
            $path = Join-Path $PSCompletions.path.completions $completion
            if (Test-Path $path) {
                $out.Path = $path
                $update = Get-Content "$path\.update" -Raw -Encoding utf8 -ErrorAction Ignore
                if ($update -and $update.Trim()) {
                    $out.Update = $update.Trim()
                }
                $updated = Get-Item "$path\.update" -ErrorAction Ignore | Select-Object -ExpandProperty LastWriteTime
                if ($updated) {
                    $out.Updated = $updated
                }
            }

            Write-Output ([PSCustomObject]$out)
        }
    }
    function _search {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'search'
            return
        }
        if (!(download_list)) {
            return
        }
        $result = $PSCompletions.list.Where({ $_ -like $arg[1] })
        if ($result) {
            $result
        }
        else {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.search.err.no))
        }
    }
    function _which {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'which'
            return
        }
        foreach ($completion in $arg[1..($arg.Length - 1)]) {
            if ($completion -in $PSCompletions.data.list) {
                Write-Output (Join-Path $PSCompletions.path.completions $completion)
            }
            else {
                $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
            }
        }
    }
    function _alias {
        $cmd_list = @('list', 'add', 'rm')
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg[1] -notin $cmd_list) {
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }

        if ($arg[1] -eq 'list') {
            $data = [System.Collections.Generic.List[System.Object]]@()
            Show-List
            return
        }

        $data_alias = [ordered]@{}
        $data_aliasMap = [ordered]@{}
        foreach ($_ in $PSCompletions.data.list) {
            $data_alias[$_] = [System.Collections.Generic.List[string]]@()
            if ($PSCompletions.data.alias[$_]) {
                foreach ($a in $PSCompletions.data.alias[$_]) {
                    $data_alias[$_].Add($a)
                    $data_aliasMap[$a] = $_
                }
            }
            else {
                $data_alias[$_].Add($_)
                $data_aliasMap[$_] = $_
            }
        }
        switch ($arg[1]) {
            'add' {
                $completion = $arg[2]
                if ($null -eq $arg[2]) {
                    $cmd_list = $PSCompletions.data.list
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.alias.add.example
                    return
                }
                else {
                    if ($arg[2] -notin $PSCompletions.data.list) {
                        Show-ParamError 'err' '' $PSCompletions.info.no_completion
                        return
                    }
                }
                if ($null -eq $arg[3]) {
                    Show-ParamError 'min' '' $PSCompletions.info.alias.add.err.min_v $PSCompletions.info.alias.add.example
                    return
                }
                $add_list = @()
                foreach ($alias in $arg[3..($arg.Length - 1)]) {
                    $alias = ($alias -split ' ')[0]
                    if ($alias -in $data_alias[$completion]) {
                        Show-ParamError 'err' '' $PSCompletions.info.alias.add.err.exist
                        Write-Host
                        continue
                    }
                    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($alias)) {
                        Show-ParamError 'err' '' $PSCompletions.info.err.has_wildcard
                        Write-Host
                        continue
                    }
                    if ($alias -eq 'PSCompletions') {
                        Show-ParamError 'err' '' $PSCompletions.info.alias.add.err.cmd_exist
                        continue
                    }
                    $has_command = Get-Command $alias -ErrorAction Ignore
                    if (($alias -notmatch '.*\.\w+$') -and $has_command.CommandType -eq 'Alias') {
                        Show-ParamError 'err' '' $PSCompletions.info.alias.add.err.cmd_exist
                        continue
                    }
                    $data_alias[$completion].Add($alias)
                    $data_aliasMap[$alias] = $completion
                    $add_list += $alias
                }
                if ($add_list.Count) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.alias.done))
                    $need_restart = $true
                }
            }
            'rm' {
                $completion = $arg[2]
                if ($null -eq $arg[2]) {
                    $cmd_list = $PSCompletions.data.list
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.alias.rm.example
                    return
                }
                else {
                    if ($arg[2] -notin $PSCompletions.data.list) {
                        Show-ParamError 'err' '' $PSCompletions.info.no_completion
                        return
                    }
                }
                if ($null -eq $arg[3]) {
                    Show-ParamError 'min' '' $PSCompletions.info.alias.rm.err.min_v $PSCompletions.info.alias.rm.example
                    return
                }

                $rm_list = @()
                foreach ($alias in $arg[3..($arg.Length - 1)]) {
                    if ($alias -in $PSCompletions.data.aliasMap.Keys) {
                        if ($data_alias[$completion].Count -gt 1) {
                            $null = $data_alias[$completion].Remove($alias)
                            $null = $data_aliasMap.Remove($alias)
                            $rm_list += $alias
                        }
                        else {
                            $PSCompletions.write_with_color((_replace ($PSCompletions.info.alias.rm.err.unique)))
                        }
                    }
                    else {
                        $PSCompletions.write_with_color((_replace ($PSCompletions.info.alias.rm.err.no_alias)))
                    }
                }
                if ($rm_list.Count) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.alias.done))
                    $need_restart = $true
                }
            }
        }
        $PSCompletions.data.alias = $data_alias
        $PSCompletions.data.list = @($data_alias.Keys)
        $PSCompletions.data.aliasMap = [ordered]@{}
        foreach ($key in $PSCompletions.data.list) {
            foreach ($a in $data_alias[$key]) {
                $PSCompletions.data.aliasMap[$a] = $key
            }
        }
        $saveData = [ordered]@{}
        foreach ($key in $PSCompletions.data.Keys) {
            if ($key -notin 'list', 'aliasMap') { $saveData[$key] = $PSCompletions.data[$key] }
        }
        $saveData | ConvertTo-Json -Depth 10 | Out-File $PScompletions.path.data -Force -Encoding utf8
        if ($need_restart) {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.module.restart))
            $need_restart = $null
        }
    }
    function _config {
        $cmd_list = $PSCompletions.config_item
        $config_item = $arg[1]
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd  $PSCompletions.info.config.example
            return
        }

        if ($arg[1] -notin $cmd_list) {
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }

        if ($arg[1] -in $cmd_list) {
            if ($arg.Length -eq 2) {
                Write-Output $PSCompletions.wrap_whitespace($PSCompletions.config.$($arg[1]))
                return
            }
        }

        function handle_done {
            param([bool]$is_can, $err_info, $example = $PSCompletions.info.config.$($arg[1]).example)
            if ($arg.Length -eq 3) {
                if ($is_can) {
                    $old_value = $PSCompletions.config.$config_item
                    $new_value = $arg[2]
                    $PSCompletions.config.$config_item = $new_value
                    $PSCompletions.need_update_data = $true
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.config.done))
                }
                else {
                    Show-ParamError 'err' '' $err_info $example
                }
            }
        }
        switch ($arg[1]) {
            'language' {
                handle_done ($arg[2] -is [string] -and $arg[2] -ne '') $PSCompletions.info.config.language.err
            }
            'url' {
                $arg[2] = $arg[2].TrimEnd('/')
                handle_done ($arg[2] -match 'http[s]?://' -or '' -eq $arg[2]) $PSCompletions.info.config.url.err
            }
            { $_ -like 'enable_*' } {
                handle_done ($arg[2] -is [int] -and $arg[2] -in 1, 0) $PSCompletions.info.config.err.one_or_zero
            }
        }
    }
    function _completion {
        $cmd_list = $PSCompletions.data.list
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.completion.example
            return
        }
        if ($arg[1] -notin $PSCompletions.data.list) {
            $cmd_list = $PSCompletions.data.list
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg.Length -lt 3) {
            Show-ParamError 'min' 'completion'
            return
        }
        $config_list = $PSCompletions.default_completion_item

        if ($null -eq $PSCompletions.config.completion.$($arg[1])) {
            $PSCompletions.config.completion.$($arg[1]) = [ordered]@{}
        }

        if ($arg[2] -notin $config_list -and $null -eq $PSCompletions.config.completion.$($arg[1]).$($arg[2])) {
            $cmd_list = $config_list + ($PSCompletions.config.completion.$($arg[1]).keys.Where({ $_ -notin $config_list }))
            $sub_cmd = $arg[2]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg.Length -eq 3) {
            Write-Output $PSCompletions.wrap_whitespace($PSCompletions.config.completion.$($arg[1]).$($arg[2]))
            return
        }

        $completion = $arg[1]
        $config_item = $arg[2]
        $old_value = $PSCompletions.config.completion[$completion].$config_item
        $new_value = $arg[3]
        if ($new_value -match '^-?\d+$') {
            $new_value = [int]$new_value
        }

        if ($config_item -match '(enable_\w+)|(disable_\w+)') {
            if ($new_value -notin 1, 0) {
                $cmd_list = $null
                $sub_cmd = $arg[2]
                $cmd_info = $PSCompletions.info.menu.config.err.v_1_or_0
                Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.completion.example
                return
            }
        }
        $PSCompletions.config.completion[$completion].$config_item = $new_value
        $PSCompletions.need_update_data = $true
        $PSCompletions.write_with_color((_replace $PSCompletions.info.completion.done))

        if ($config_item -eq 'language' -and $PSCompletions.config.enable_cache) {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.module.restart))
        }
    }
    function _menu {
        $cmd_list = @('symbol', 'line_theme', 'color_theme', 'custom', 'config')
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'menu' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg[1] -notin $cmd_list) {
            Show-ParamError 'err' 'menu' $PSCompletions.info.sub_cmd
        }
        switch ($arg[1]) {
            'symbol' {
                $cmd_list = @('SpaceTab', 'WriteSpaceTab', 'OptionTab')
                if ($arg.Length -eq 2) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.$($arg[1]).example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    $sub_cmd = $arg[2]
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.$($arg[1]).example
                }
                $config_item = $arg[2]
                if ($arg.Length -eq 3) {
                    Write-Output $PSCompletions.wrap_whitespace($PSCompletions.config.$config_item)
                    return
                }
                if ($arg.Length -ge 4) {
                    $old_value = $PSCompletions.config.$config_item
                    $new_value = $arg[3]
                    $PSCompletions.config.$config_item = $arg[3]
                    $PSCompletions.need_update_data = $true
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.done))
                }
            }
            'line_theme' {
                if ($PSEdition -eq 'Desktop') {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.err.deny_change_menu_line_style))
                    return
                }

                $cmd_list = @('double_line_rect_border', 'bold_line_rect_border', 'single_line_rect_border', 'single_line_round_border', 'boldTB_slimLR_border', 'slimTB_boldLR_border', 'doubleTB_singleLR_border', 'singleTB_doubleLR_border')
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.line_theme.example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.line_theme.example
                    return
                }
                switch ($arg[2]) {
                    # [int][char]"═"
                    'double_line_rect_border' {
                        $PSCompletions.config.horizontal = [string][char]9552 # ═
                        $PSCompletions.config.vertical = [string][char]9553 # ║
                        $PSCompletions.config.top_left = [string][char]9556 # ╔
                        $PSCompletions.config.bottom_left = [string][char]9562 # ╚
                        $PSCompletions.config.top_right = [string][char]9559 # ╗
                        $PSCompletions.config.bottom_right = [string][char]9565 # ╝
                    }
                    'bold_line_rect_border' {
                        $PSCompletions.config.horizontal = [string][char]9473 # ━
                        $PSCompletions.config.vertical = [string][char]9475 # ┃
                        $PSCompletions.config.top_left = [string][char]9487 # ┏
                        $PSCompletions.config.bottom_left = [string][char]9495 # ┗
                        $PSCompletions.config.top_right = [string][char]9491 # ┓
                        $PSCompletions.config.bottom_right = [string][char]9499 # ┛
                    }
                    'single_line_rect_border' {
                        $PSCompletions.config.horizontal = [string][char]9472 # ─
                        $PSCompletions.config.vertical = [string][char]9474 # │
                        $PSCompletions.config.top_left = [string][char]9484 # ┌
                        $PSCompletions.config.bottom_left = [string][char]9492 # └
                        $PSCompletions.config.top_right = [string][char]9488 # ┐
                        $PSCompletions.config.bottom_right = [string][char]9496 # ┘
                    }
                    'single_line_round_border' {
                        $PSCompletions.config.horizontal = [string][char]9472 # ─
                        $PSCompletions.config.vertical = [string][char]9474 # │
                        $PSCompletions.config.top_left = [string][char]9581 # ╭
                        $PSCompletions.config.bottom_left = [string][char]9584 # ╰
                        $PSCompletions.config.top_right = [string][char]9582 # ╮
                        $PSCompletions.config.bottom_right = [string][char]9583 # ╯
                    }
                    # TB: top and bottom
                    # LR: left and right
                    'boldTB_slimLR_border' {
                        $PSCompletions.config.horizontal = [string][char]9473 # ━
                        $PSCompletions.config.vertical = [string][char]9474 # │
                        $PSCompletions.config.top_left = [string][char]9485 # ┍
                        $PSCompletions.config.bottom_left = [string][char]9493 # ┕
                        $PSCompletions.config.top_right = [string][char]9489 # ┑
                        $PSCompletions.config.bottom_right = [string][char]9497 # ┙
                    }
                    'slimTB_boldLR_border' {
                        $PSCompletions.config.horizontal = [string][char]9472 # ─
                        $PSCompletions.config.vertical = [string][char]9475 # ┃
                        $PSCompletions.config.top_left = [string][char]9486 # ┎
                        $PSCompletions.config.bottom_left = [string][char]9494 # ┖
                        $PSCompletions.config.top_right = [string][char]9490 # ┒
                        $PSCompletions.config.bottom_right = [string][char]9498 # ┚
                    }
                    'doubleTB_singleLR_border' {
                        $PSCompletions.config.horizontal = [string][char]9552 # ═
                        $PSCompletions.config.vertical = [string][char]9474 # │
                        $PSCompletions.config.top_left = [string][char]9554 # ╒
                        $PSCompletions.config.bottom_left = [string][char]9560 # ╘
                        $PSCompletions.config.top_right = [string][char]9557 # ╕
                        $PSCompletions.config.bottom_right = [string][char]9563 # ╛
                    }
                    'singleTB_doubleLR_border' {
                        $PSCompletions.config.horizontal = [string][char]9472 # ─
                        $PSCompletions.config.vertical = [string][char]9553 # ║
                        $PSCompletions.config.top_left = [string][char]9555 # ╓
                        $PSCompletions.config.bottom_left = [string][char]9561 # ╙
                        $PSCompletions.config.top_right = [string][char]9558 # ╖
                        $PSCompletions.config.bottom_right = [string][char]9564 # ╜
                    }
                }
                $PSCompletions.need_update_data = $true
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.line_theme.done))
            }
            'color_theme' {
                $pure_color_list = @('Red', 'DarkRed', 'Blue', 'DarkBlue', 'Green', 'DarkGreen', 'Cyan', 'DarkCyan', 'Yellow', 'DarkYellow', 'Magenta', 'DarkMagenta', 'Gray', 'DarkGray')
                $cmd_list = @('Default') + $pure_color_list
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.color_theme.example
                    return
                }
                switch ($arg[2]) {
                    'Default' {
                        $PSCompletions.config.filter_color = 'Yellow'
                        $PSCompletions.config.border_color = 'DarkGray'
                        $PSCompletions.config.item_color = 'Blue'
                        $PSCompletions.config.status_color = 'Blue'
                        $PSCompletions.config.tip_color = 'Cyan'

                        $PSCompletions.config.selected_color = 'White'
                        $PSCompletions.config.selected_bgcolor = 'DarkGray'
                    }
                    { $_ -in $pure_color_list } {
                        $PSCompletions.config.filter_color = $_
                        $PSCompletions.config.border_color = $_
                        $PSCompletions.config.item_color = $_
                        $PSCompletions.config.status_color = $_
                        $PSCompletions.config.tip_color = $_

                        $PSCompletions.config.selected_color = 'White'
                        $PSCompletions.config.selected_bgcolor = $_
                    }
                    default {
                        Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.color_theme.example
                        return
                    }
                }
                $PSCompletions.need_update_data = $true
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.color_theme.done))
            }
            'custom' {
                $cmd_list = @('color', 'line')
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg[2] -eq 'line' -and $PSEdition -eq 'Desktop') {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.err.deny_change_menu_line_style))
                    return
                }
                if ($arg.Length -lt 4) {
                    $cmd_list = $PSCompletions.menu.const."$($arg[2])_item"
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg[3] -notin $PSCompletions.menu.const."$($arg[2])_item") {
                    $cmd_list = $PSCompletions.menu.const."$($arg[2])_item"
                    Show-ParamError 'err'  '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg.Length -lt 5) {
                    Write-Output $PSCompletions.wrap_whitespace($PSCompletions.config[$arg[3]])
                    return
                }
                if ($arg.Length -gt 5) {
                    if ($arg[2] -eq 'color' -and $arg[4] -notin $PSCompletions.menu.const.color_value) {
                        $cmd_list = $PSCompletions.menu.const.color_value
                        Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                        return
                    }
                }
                $config_item = $arg[3]
                $old_value = $PSCompletions.config.$config_item
                $new_value = $arg[4]
                $PSCompletions.config.$config_item = $new_value
                $PSCompletions.need_update_data = $true
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.done))
            }
            'config' {
                $cmd_list = $PSCompletions.menu.const.config_item
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                    return
                }
                if ($arg.Length -eq 3) {
                    Write-Output $PSCompletions.wrap_whitespace($PSCompletions.config.$($arg[2]))
                    return
                }
                if ($arg[3] -match '^-?\d+$') {
                    $value = [int]$arg[3]
                    $is_num = $true
                }
                else {
                    $value = $arg[3]
                    $is_num = $false
                }

                switch ($arg[2]) {
                    'trigger_key' {
                        try {
                            if ($arg[3] -ne $PSCompletions.config.trigger_key) {
                                Remove-PSReadLineKeyHandler $PSCompletions.config.trigger_key
                                if (($IsWindows -or $PSEdition -eq 'Desktop') -and $PSCompletions.config.enable_menu -and $PSCompletions.config.enable_menu_enhance) {
                                    Set-PSReadLineKeyHandler -Key $arg[3] -ScriptBlock $PSCompletions.menu.module_completion_menu_script
                                }
                                else {
                                    Set-PSReadLineKeyHandler $arg[3] MenuComplete
                                }
                            }
                        }
                        catch {
                            Show-ParamError 'err' 'trigger_key' $PSCompletions.info.menu.config.err.trigger_key
                            return
                        }
                    }
                    { $_ -in 'list_min_width', 'list_max_count_when_above', 'list_max_count_when_below', 'completions_confirm_limit' } {
                        $min = 0
                        if (!$is_num -or $value -lt $min) {
                            $cmd_list = $null
                            $sub_cmd = $value
                            $cmd_info = _replace $PSCompletions.info.menu.config.err.v_ge
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                    { $_ -in 'height_from_menu_bottom_to_cursor_when_above', 'height_from_menu_top_to_cursor_when_below' } {
                        $min = 0
                        $max = 5
                        if (!$is_num -or $value -lt $min -or $value -gt $max) {
                            $cmd_list = $null
                            $sub_cmd = $value
                            $cmd_info = _replace $PSCompletions.info.menu.config.err.v_ge_le
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                    { $_ -in ($PSCompletions.menu.const.config_item | Where-Object { $_ -match '(enable_\w+)|(disable_\w+)' }) } {
                        if (!$is_num -or $value -notin 1, 0) {
                            $cmd_list = $null
                            $sub_cmd = $value
                            $cmd_info = $PSCompletions.info.menu.config.err.v_1_or_0
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                    'filter_symbol' {
                        if ($value.Trim().Length -lt 2) {
                            Show-ParamError 'err' 'filter_symbol' $PSCompletions.info.menu.config.err.filter_symbol
                            return
                        }
                    }
                    'completion_suffix' {
                        if ($value -notmatch '^\s*$') {
                            Show-ParamError 'err' 'completion_suffix' $PSCompletions.info.menu.config.err.completion_suffix
                            return
                        }
                    }
                }
                $config_item = $arg[2]
                $old_value = $PSCompletions.config.$config_item
                $new_value = $value
                $PSCompletions.config.$config_item = $new_value
                $PSCompletions.need_update_data = $true
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.done))
                if ($config_item -in 'enable_menu', 'enable_menu_enhance', 'trigger_key') {
                    $PSCompletions.handle_completion()
                }
            }
        }
    }
    function _reset {
        $cmd_list = @('--all', 'config', 'alias', 'order', 'completion', 'menu')
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.example
            return
        }
        if ($arg[1] -notin $cmd_list) {
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.example
            return
        }

        if ($arg[1] -in 'alias', 'completion', 'menu') {
            $cmd_list = @('--all')
            if ($arg[1] -in 'alias', 'completion') {
                $cmd_list += $PSCompletions.data.list
            }
            elseif ($arg[1] -eq 'menu') {
                $cmd_list += @('symbol', 'line', 'color', 'config')
            }
            if ($arg.Length -eq 2) {
                Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.$($arg[1]).example
                return
            }
            if ($arg[1] -notin 'completion', 'alias' -and $arg.Length -gt 3) {
                Show-ParamError 'max' '' '' $PSCompletions.info.reset.$($arg[1]).example
                return
            }
        }
        else {
            if ($arg.Length -ne 2) {
                $cmd_list = $null
                Show-ParamError 'max' '' '' $PSCompletions.info.reset.example
                return
            }
        }
        function handle_reset {
            param([array]$configs)
            $change_list = [System.Collections.Generic.List[System.Object]]@()
            foreach ($_ in $configs) {
                $change_list.Add(@{
                        item      = $_
                        old_value = $PSCompletions.config.$_
                        new_value = $PSCompletions.default_config.$_
                    })
                $PSCompletions.config."$_" = $PSCompletions.default_config.$_
                $PSCompletions.need_update_data = $true
            }
            return $change_list
        }
        switch ($arg[1]) {
            'config' {
                $change_list = handle_reset $PSCompletions.config_item
            }
            'alias' {
                $need_restart = $true
                $change_list = [System.Collections.Generic.List[System.Object]]@()
                $del_list = if ($arg[2] -eq '--all') { , $PSCompletions.data.list }else { , $arg[2..($arg.Length - 1)] }
                foreach ($completion in $del_list) {
                    if ($completion -in $PSCompletions.data.list) {
                        $old_value = $PSCompletions.data.alias[$completion] -join ' '
                        $null = $PSCompletions.data.alias.Remove($completion)
                        $alias = ($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$completion/config.json") | ConvertFrom-Json).alias
                        $new_value = if ($alias) { $alias }else { $completion }
                        $PSCompletions.data.alias[$completion] = @($new_value)
                        $PSCompletions.need_update_data = $true
                        $change_list.Add(@{
                                item      = $completion
                                old_value = $old_value
                                new_value = $new_value
                            })
                    }
                    else {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
                    }
                }
                $PSCompletions.data.list = @($PSCompletions.data.alias.Keys)
                $PSCompletions.data.aliasMap = [ordered]@{}
                foreach ($_ in $PSCompletions.data.list) {
                    if ($PSCompletions.data.alias[$_]) {
                        foreach ($a in $PSCompletions.data.alias.$_) {
                            $PSCompletions.data.aliasMap."$a" = $_
                            $PSCompletions.need_update_data = $true
                        }
                    }
                    else {
                        $PSCompletions.data.aliasMap."$_" = $_
                        $PSCompletions.need_update_data = $true
                    }
                }
            }
            'order' {
                foreach ($_ in Get-ChildItem $PSCompletions.path.order) {
                    Remove-Item $_.FullName -Force -Recurse -ErrorAction Ignore
                }
                $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.order.done))
                return
            }
            'completion' {
                $old_config = $PSCompletions.config.completion.Clone()
                $change_list = [System.Collections.Generic.List[System.Object]]@()
                $list = if ($arg | Where-Object { $_ -eq '--all' }) { $PSCompletions.data.list } else { $arg[2..($arg.Length - 1)] }
                foreach ($c in $list) {
                    $PSCompletions.config.completion[$c] = [ordered]@{}
                    $path = "$($PSCompletions.path.completions)/$c/config.json"
                    $json_config = $PSCompletions.get_raw_content($path) | ConvertFrom-Json
                    if ($null -eq $json_config) { continue }
                    $path = "$($PSCompletions.path.completions)/$c/language/$($json_config.language[0]).json"
                    $json = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($path))
                    foreach ($item in $json.config) {
                        $PSCompletions.config.completion[$c].$($item.name) = $item.value
                        $change_list.Add(@{
                                cmd       = $c
                                item      = $item.name
                                old_value = $old_config[$c].$($item.name)
                                new_value = $item.value
                            })
                    }
                    foreach ($item in $PSCompletions.default_completion_item) {
                        if ($null -ne $old_config[$c].$item) {
                            $change_list.Add(@{
                                    cmd       = $c
                                    item      = $item
                                    old_value = $old_config[$c].$($item)
                                    new_value = $null
                                })
                        }
                    }
                    if ($null -ne $json_config.hooks) {
                        $PSCompletions.config.completion[$c].enable_hooks = [int]$json_config.hooks
                        $change_list.Add(@{
                                cmd       = $c
                                item      = $item
                                old_value = $old_config[$c].enable_hooks
                                new_value = [int]$json_config.hooks
                            })
                    }
                    $PSCompletions.need_update_data = $true
                }
            }
            'menu' {
                $cmd_list = @('--all', 'symbol', 'line', 'color', 'config')
                if ($arg[2] -notin $cmd_list) {
                    $sub_cmd = $arg[2]
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.example
                    return
                }
                switch ($arg[2]) {
                    'symbol' {
                        $change_list = handle_reset $PSCompletions.menu.const.symbol_item
                    }
                    'line' {
                        $change_list = handle_reset $PSCompletions.menu.const.line_item
                    }
                    'color' {
                        $change_list = handle_reset $PSCompletions.menu.const.color_item
                    }
                    'config' {
                        $need_restart = $true
                        $change_list = handle_reset $PSCompletions.menu.const.config_item
                    }
                    '--all' {
                        $need_restart = $true
                        $change_list = [System.Collections.Generic.List[System.Object]]@()
                        $change_list += handle_reset $PSCompletions.menu.const.symbol_item
                        $change_list += handle_reset $PSCompletions.menu.const.line_item
                        $change_list += handle_reset $PSCompletions.menu.const.color_item
                        $change_list += handle_reset $PSCompletions.menu.const.config_item
                    }
                }
            }
            '--all' {
                $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.reset.init_confirm))
                while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode) {
                    if ($PressKey.ControlKeyState -notlike '*CtrlPressed*') {
                        if ($PressKey.VirtualKeyCode -eq 13) {
                            # 13: Enter
                            Remove-Item $PSCompletions.path.temp -Force -Recurse -ErrorAction Ignore
                            '{}' | Out-File $PSCompletions.path.data -Encoding utf8 -ErrorAction Ignore

                            foreach ($_ in Get-ChildItem $PSCompletions.path.completions -Force -Recurse) {
                                Remove-Item $_.FullName -Force -Recurse -ErrorAction Ignore
                            }

                            $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.init_done))
                            $PSCompletions.init_data()
                        }
                        else {
                            $PSCompletions.write_with_color($PSCompletions.replace_content($PSCompletions.info.confirm_cancel))
                        }
                        break
                    }
                }
                return
            }
        }
        $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.done))
        if ($need_restart) {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.module.restart))
            $need_restart = $null
        }
    }
    function _help {
        $json = $PSCompletions.completions.psc
        $info = $PSCompletions.info
        $PSCompletions.write_with_color((_replace $PSCompletions.info.description))
    }
    $need_init = $true
    $PSCompletions.need_update_data = $null
    switch ($arg[0]) {
        'list' {
            _list
            $need_init = $false
        }
        'add' {
            _add
        }
        'rm' {
            _rm
        }
        'update' {
            _update
        }
        'info' {
            _info
        }
        'search' {
            _search
            $need_init = $false
        }
        'which' {
            _which
            $need_init = $false
        }
        'alias' {
            _alias
        }
        'config' {
            _config
        }
        'completion' {
            _completion
        }
        'menu' {
            _menu
        }
        'reset' {
            _reset
        }
        default {
            # https://pscompletions.abgox.com/docs/source-profile
            $PSCompletions.init_data()
            $PSCompletions.handle_completion()
            _help
            return
        }
    }
    Out-Data
    if ($need_init) { $PSCompletions.init_data() }
}

Export-ModuleMember -Function PSCompletions
