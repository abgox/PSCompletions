. $PSScriptRoot\replace.ps1

function _psc_download_list {
    try {
        $response = Invoke-WebRequest -Uri ($_psc.url + '/core/.list')
        if ($response.StatusCode -eq 200) {
            $content = ($response.Content).Trim()
            Move-Item  $_psc.list_path  $_psc.old_list_path -Force
            echo $content > $_psc.list_path
            $_psc.list = _psc_get_content $_psc.list_path
        }
    }
    catch {  }
}

function _psc_add_completion($completion, $log = $true, $is_update = $false) {
    if ($is_update) {
        $add_error = $_psc.json.update_download_error
        $add_completed = $_psc.json.update_completed
    }
    else {
        $add_error = $_psc.json.add_download_error
        $add_completed = $_psc.json.add_completed
    }
    $url = $_psc.url + '/completions/' + $completion
    function _mkdir($path) {
        if (!(Test-Path($path))) { mkdir $path > $null }
    }
    $completion_dir = $_psc.completions + '\' + $completion
    _mkdir $_psc.completions
    _mkdir $completion_dir
    _mkdir ($completion_dir + '\json')

    $files = @(
        @{
            Uri     = $url + '/' + $completion + '.ps1'
            OutFile = $completion_dir + '\' + $completion + '.ps1'
        },
        @{
            Uri     = $url + '/json/zh-CN.json'
            OutFile = $completion_dir + '\json\zh-CN.json'
        },
        @{
            Uri     = $url + '/json/en-US.json'
            OutFile = $completion_dir + '\json\en-US.json'
        },
        @{
            Uri     = $url + "/.guid"
            OutFile = $completion_dir + '\.guid'
        }
    )
    $jobs = @()
    foreach ($file in $files) {
        $jobs += Start-Job -Name $file.OutFile -ScriptBlock {
            $params = $using:file
            Invoke-WebRequest @params
        }
    }
    if ($is_update) {
        $flag = $_psc.json.updating
    }
    else {
        $flag = $_psc.json.adding
    }
    Write-Host (_psc_replace $flag) -f Yellow
    Wait-Job -Job $jobs > $null

    $all_exist = $true
    foreach ($file in $files) {
        if (-not (Test-Path $file.OutFile)) {
            $all_exist = $false
            $fail_file = $file.OutFile
        }
    }

    if ($all_exist) {
        if ($log) {
            Write-Host  (_psc_replace $add_completed) -f Green
            Write-Host (_psc_replace ($_psc.json.download_dir + $completion_dir)) -f Green
        }
    }
    else {
        Write-Host  (_psc_replace $add_error) -f Red
        rmdir $completion_dir -Force -Recurse > $null
    }
}

function _psc_get_config {
    $config = [environment]::GetEnvironmentvariable("abgox_PSCompletions", "User") -split ';'
    $config = @{
        'module_version' = $config[0]
        'root_cmd'       = $config[1]
        'github'         = $config[2]
        'gitee'          = $config[3]
        'language'       = $config[4]
        'update'         = $config[5]
    }
    return $config
}

function _psc_set_config($key, $value) {
    $config = _psc_get_config
    $config.$key = $value
    $res = $config.module_version + ';' + $config.root_cmd + ';' + $config.github + ';' + $config.gitee + ';' + $config.language + ';' + $config.update
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
}

function _psc_get_content($path) {
    try {
        return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue)
    }
    catch { return "" }
}

function _psc_get_cmd($path, $cmd) {
    $p = $path + '\.alias'
    if (Test-Path($p)) {
        $c = _psc_get_content $p
        $r = (($c -split '\s+')).Count
        if ($r -eq 1) {
            return $c
        }
        elseif ($r -gt 1) {
            $res = ($c -split ' ')[0]
            echo $res > $p
            return $res
        }
    }
    return $cmd
}
