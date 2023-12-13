$PSCompletions | Add-Member -MemberType ScriptMethod fn_download_list {
    try {
        if ($PSCompletions.url) {
            $res = Invoke-WebRequest -Uri ($PSCompletions.url + '/list.txt')
            if ($res.StatusCode -eq 200) {
                $content = $res.Content.Trim()
                $old_list = $PSCompletions.fn_get_raw_content($PSCompletions.path.old_list)
                $list = $PSCompletions.fn_get_raw_content($PSCompletions.path.list)
                if ($old_list -ne $list) {
                    Copy-Item $PSCompletions.path.list $PSCompletions.path.old_list -Force
                }
                if ($content -ne $list) {
                    $content | Out-File $PSCompletions.path.list -Force -Encoding utf8
                    $PSCompletions.list = $PSCompletions.fn_get_content($PSCompletions.path.list)
                }
                return $content
            }
        }
        else {
            $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.repo_add))
            return $false
        }
    }
    catch { return $false }
}

$PSCompletions | Add-Member -MemberType ScriptMethod fn_add_completion {
    param (
        [string]$completion,
        [bool]$log = $true,
        [bool]$is_update = $false
    )
    if ($is_update) {
        $err = $PSCompletions.json.update_download_err
        $done = $PSCompletions.json.update_done
    }
    else {
        $err = $PSCompletions.json.add_download_err
        $done = $PSCompletions.json.add_done
    }
    $url = $PSCompletions.url + '/completions/' + $completion
    function _mkdir($path) {
        if (!(Test-Path($path))) { New-Item -ItemType Directory $path > $null }
    }
    $completion_dir = $PSCompletions.path.completions + '\' + $completion
    _mkdir $PSCompletions.path.completions
    _mkdir $completion_dir
    _mkdir ($completion_dir + '\lang')

    $files = @(
        @{
            Uri     = $url + '/' + $completion + '.ps1'
            OutFile = $completion_dir + '\' + $completion + '.ps1'
        },
        @{
            Uri     = $url + '/lang/zh-CN.json'
            OutFile = $completion_dir + '\lang\zh-CN.json'
        },
        @{
            Uri     = $url + '/lang/en-US.json'
            OutFile = $completion_dir + '\lang\en-US.json'
        },
        @{
            Uri     = $url + '/guid.txt'
            OutFile = $completion_dir + '\guid.txt'
        }
    )
    $wc = New-Object System.Net.WebClient
    foreach ($file in $files) {
        $wc.DownloadFile($file.Uri, $file.OutFile)
    }
    $download = if ($is_update) { $PSCompletions.json.updating }else { $PSCompletions.json.adding }
    $PSCompletions.fn_write($PSCompletions.fn_replace($download))

    $all_exist = $true
    foreach ($file in $files) {
        if (!(Test-Path $file.OutFile)) {
            $all_exist = $false
            $fail_file = Split-Path $file.OutFile -Leaf
            $fail_file_url = $file.Uri
        }
    }
    if ($all_exist) {
        if ($log) {
            $PSCompletions.fn_write($PSCompletions.fn_replace($done))
        }
    }
    else {
        $PSCompletions.fn_write($PSCompletions.fn_replace($err))
        Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue
    }

    $core_info = ($PSCompletions.fn_get_raw_content($completion_dir + '\lang\' + $PSCompletions.lang + '.json') | ConvertFrom-Json).$($completion + '_core_info')
    if ($core_info.comp_config) {
        $configs = $core_info.comp_config.PSObject.Properties.Name

        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.comp_config_tip))
        foreach ($config in $configs) {
            $PSCompletions.fn_write($PSCompletions.fn_replace($core_info.comp_config.$config))
        }
        $PSCompletions.has_config_update = $true
    }
}
