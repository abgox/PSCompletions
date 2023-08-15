function _psc_download_file($url, $outPath, $log = $true, $is_update = $false) {
    if ($is_update) {
        $flag = $_psc.json.update_start
    }
    else {
        $flag = $_psc.json.download_start
    }
    $webClient = New-Object System.Net.WebClient
    if ($log) {
        $fileName = Split-Path $url -Leaf
        $completion = Split-Path (Split-Path $url -Parent) -Leaf
        try {
            Write-Host ($flag + $url) -f Yellow -NoNewline
            $webClient.DownloadFile($url, $outPath)
            Write-Host $_psc.json.download_end -f Green
        }
        catch {
            throw ($_psc.json.download_fail + '@@' + $completion + '@@' + $fileName)
        }
    }
    else { try { $webClient.DownloadFile($url, $outPath) }catch {} }
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
    $url_ps1 = $url + '/' + $completion + '.ps1'
    function _mkdir($path) {
        if (!(Test-Path($path))) { mkdir $path > $null }
    }
    $completion_dir = $_psc.completions + '\' + $completion
    _mkdir $_psc.completions
    _mkdir $completion_dir
    _mkdir ($completion_dir + '\json')
    try {
        _psc_download_file ($url + '/.guid') ($completion_dir + '\.guid') $log $is_update
        _psc_download_file $url_ps1 ($completion_dir + '\' + $completion + '.ps1') $log $is_update
        foreach ($_ in $_psc.langs) {
            _psc_download_file ($url + '/json/' + $_ + '.json') ($completion_dir + '\json\' + $_ + '.json') $log $is_update
        }
    }
    catch {
        if ($log) {
            $err = $_.Exception.Message -split '@@'
            $completion = $err[1]
            $file = $err[2]
            Write-Host $err[0] -f Red
            Write-Host  (_psc_replace $add_error  @{'completion' = $completion; 'file' = $file }) -f Red
        }
        if (Test-Path($completion_dir)) {
            rmdir $completion_dir -Force -Recurse > $null
        }
    }
    if (Test-Path($completion_dir)) {
        if ($log) {
            Write-Host  (_psc_replace $add_completed @{'completion' = $completion }) -f Green
            Write-Host ($_psc.json.download_dir + $completion_dir) -f Green
        }
    }
}

function _psc_get_config {
    $config = [environment]::GetEnvironmentvariable("abgox_PSCompletions", "User") -split ';'
    $config = @{
        'root_cmd' = $config[0]
        'github'   = $config[1]
        'gitee'    = $config[2]
        'language' = $config[3]
        'update'   = $config[4]
        'guid'     = $config[5]
        'time'     = $config[6]
    }
    return $config
}

function _psc_set_config($key, $value) {
    $config = _psc_get_config
    $config.$key = $value
    $res = $config.root_cmd + ';' + $config.github + ';' + $config.gitee + ';' + $config.language + ';' + $config.update + ';' + $config.guid + ';' + $config.time
    [environment]::SetEnvironmentvariable('abgox_PSCompletions', $res, 'User')
}

function _psc_get_content($path) {
    try {
        return (Get-Content $path -Encoding utf8).Trim()
    }
    catch {
        return ""
    }

}

function _psc_replace($content, $var_list = @{}) {
    $var_list.'root_cmd' = $_psc.config.root_cmd
    $list = @{}
    $result = $content
    function _do($var, $value) {
        $var = $var -replace "'", ""
        $variables = @{}
        $list[$var] = $value
    }
    foreach ($_ in $var_list.keys) {
        _do $_ $var_list.$_
    }
    $match = [regex]::Match($content, '@\{\{([^}]+)\}\}')
    if ($match.Success) {
        $replace_list = Invoke-Expression ('@{' + $match.Groups[1].Value + '}')
        $list += $replace_list
        $res = [System.Text.RegularExpressions.Regex]::Replace(
            $result,
            $pattern,
            {
                param ($match)
                $key = $match.Groups[1].Value
                if ($list.ContainsKey($key)) { $list[$key] }
                else { $match.Value }
            }
        )
        $result = $res.Replace($match.Value, '')
    }
    $pattern = '\$\{\{([^}]+)\}\}'
    return [System.Text.RegularExpressions.Regex]::Replace(
        $result,
        $pattern,
        {
            param ($match)
            $key = $match.Groups[1].Value
            if ($list.ContainsKey($key)) {
                $list[$key]
            }
            else {
                $match.Value
            }
        }
    )
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

function _psc_download_list {
    $response = Invoke-WebRequest -Uri ($_psc.url + '/core/.guid')
    if ($response.StatusCode -eq 200) {
        $content = ([System.Text.Encoding]::UTF8.GetString($response.Content)).Trim()
        if ($_psc.config.guid -ne $content) {
            if (Test-Path($_psc.list_path)) {
                Copy-Item $_psc.list_path ($_psc.core + '\.old_list') -Force
            }
            _psc_download_file ($_psc.url + '/core/.list') $_psc.list_path $false
            _psc_set_config 'guid' $content
        }
    }
    $_psc.list = _psc_get_content $_psc.list_path
}

function _psc_check_update {
    _psc_download_list
    $res = New-Object System.Collections.ArrayList
    foreach ($_ in $_psc.installed.BaseName) {
        $url = $_psc.url + '/completions/' + $_ + '/.guid'
        $response = Invoke-WebRequest -Uri  $url
        if ($response.StatusCode -eq 200) {
            $content = ([System.Text.Encoding]::UTF8.GetString($response.Content)).Trim()
            $guid = (_psc_get_content ($_psc.completions + '\' + $_ + '\.guid')).Trim()
            if ($guid -ne $content) { $res.Add($_) > $null }
        }
        echo ($res -join ',') > ($_psc.core + '\.update')
    }
    return $res
}
