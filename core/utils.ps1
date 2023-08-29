. $PSScriptRoot\replace.ps1

function _psc_get_config {
    $c = [environment]::GetEnvironmentvariable("abgox_PSCompletions", "User") -split ';'
    return @{
        module_version = $c[0]
        root_cmd       = $c[1]
        github         = $c[2]
        gitee          = $c[3]
        language       = $c[4]
        update         = $c[5]
    }
}

function _psc_set_config($k, $v) {
    $c = _psc_get_config
    $c.$k = $v
    $res = @($c.module_version, $c.root_cmd, $c.github, $c.gitee, $c.language, $c.update) -join ';'
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
}

function _psc_confirm($tip,$confirm_event) {
    Write-Host (_psc_replace $tip) -f Yellow
    $choice = $host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
    if ($choice.Character -eq 13) {
        & $confirm_event
    }
    else { Write-Host (_psc_replace $_psc.json.cancel) -f Green }
}

function _psc_get_content($path) {
    return (Get-Content $path -Encoding utf8 -ErrorAction SilentlyContinue)
}

function _psc_download_list {
    try {
        $res = Invoke-WebRequest -Url ($_psc.url + '/core/.list')
        if ($res.StatusCode -eq 200) {
            $content = ($res.Content).Trim()
            Move-Item  $_psc.path.list $_psc.path.old_list -Force
            $content | Set-Content $_psc.path.list -Force
            $_psc.list = $content
        }
    }
    catch {  }
}

function _psc_add_completion($completion, $log = $true, $is_update = $false) {
    if ($is_update) {
        $err = $_psc.json.update_download_err
        $done = $_psc.json.update_done
    }
    else {
        $err = $_psc.json.add_download_err
        $done = $_psc.json.add_done
    }
    $url = $_psc.url + '/completions/' + $completion
    function _mkdir($path) {
        if (!(Test-Path($path))) { mkdir $path > $null }
    }
    $completion_dir = $_psc.path.completions + '\' + $completion
    _mkdir $_psc.path.completions
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
        $params = $file
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
        if (!(Test-Path $file.OutFile)) {
            $all_exist = $false
            $fail_file = Split-Path $file.OutFile -Leaf
            $fail_file_url = $file.Uri
        }
    }
    if ($all_exist) {
        if ($log) {
            Write-Host  (_psc_replace $done) -f Green
            Write-Host (_psc_replace ($_psc.json.download_dir + $completion_dir)) -f Green
        }
    }
    else {
        Write-Host  (_psc_replace $err) -f Red
        Remove-Item $completion_dir -Force -Recurse > $null
    }
}
