$PSCompletions | Add-Member -MemberType ScriptMethod fn_get_order {
    param (
        [string]$PSScriptRoots,
        [array]$exclude = @(),
        [string]$file = 'order.json'
    )
    $path_order = $PSScriptRoots + '/' + $file

    if (!(Test-Path $path_order)) {
        $json = $PSCompletions.fn_get_raw_content($PSScriptRoots + '/lang/' + $PSCompletions.lang + '.json') | ConvertFrom-Json
        $i = 1
        $res = [ordered]@{}
        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $exclude
        } | ForEach-Object {
            $res.$_ = $i
            $i++
        }
        $res | ConvertTo-Json | Out-File $path_order -Force
    }
    return ($PSCompletions.fn_get_raw_content($path_order) | ConvertFrom-Json)
}
$PSCompletions | Add-Member -MemberType ScriptMethod fn_cache {
    param (
        [string]$PSScriptRoots,
        [array]$exclude = @((Split-Path $PSScriptRoots -Leaf) + '_core_info')
    )
    $origin_cmd = Split-Path $PSScriptRoots -Leaf
    $root_cmd = $PSCompletions.comp_cmd.$origin_cmd
    if ($PSCompletions.jobs.State -eq 'Completed') {
        $flag = Receive-Job $PSCompletions.jobs
        if ($flag) { $PSCompletions.comp_data = $flag }
    }
    try { Remove-Job $PSCompletions.jobs }catch {}

    if (!$PSCompletions.comp_data.$root_cmd) {
        $PSCompletions.comp_data.$root_cmd = @{}
        if ($PSCompletions.comp_config.$origin_cmd.language) {
            $lang = $PSCompletions.comp_config.$origin_cmd.language
        }
        else {
            $lang = $PSCompletions.lang
        }

        $json = $PSCompletions.fn_get_raw_content($PSScriptRoots + '/lang/' + $lang + '.json') | ConvertFrom-Json

        $PSCompletions.comp_data.$($root_cmd + '_info') = @{
            core_info = $json.$($exclude[0])
            exclude   = $exclude
            num       = -1
        }
        $common_options = $json.$($exclude[0]).common_options
        $order = $PSCompletions.fn_get_order($PSScriptRoots, $PSCompletions.comp_data.$($root_cmd + '_info').exclude)

        $_i = 1
        $__i = 999999
        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $PSCompletions.comp_data.$($root_cmd + '_info').exclude
        } | ForEach-Object {
            $cmd = $_ -split ' '
            $_o = if ($order.$_) { $order.$_ }else { $_i }
            $PSCompletions.comp_data.$root_cmd[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_, $_o)
            $_i++
            if ($common_options) {
                foreach ($item in $common_options.PSObject.Properties.Name) {
                    $PSCompletions.comp_data.$root_cmd[$root_cmd + ' ' + $_ + ' ' + $item] = @($item, $common_options.$item, $__i)
                    $__i++
                }
            }
        }
        if ($common_options) {
            foreach ($item in $common_options.PSObject.Properties.Name) {
                $PSCompletions.comp_data.$root_cmd[$root_cmd + ' ' + $item] = @($item, $common_options.$item, $__i)
                $__i++
            }
        }
    }
}
$PSCompletions | Add-Member -MemberType ScriptMethod fn_order_job {
    param (
        [string]$PSScriptRoots,
        [string]$root_cmd
    )
    $PSCompletions.jobs = Start-Job -ScriptBlock {
        param(
            $PSCompletions,
            $cmd,
            $PSScriptRoots,
            $path_history
        )
        # LRU
        if ($PSCompletions.comp_data.Count -gt [int]$PSCompletions.config.LRU * 2) {
            $PSCompletions.comp_data.RemoveAt(0)
            $PSCompletions.comp_data.RemoveAt(0)
        }
        try {
            $history = [array](Get-Content $path_history -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { ($_ -split '\s+')[0] -eq $cmd })
            $history = $history[-1] -split ' '
            function fn([array]$history) {
                $_i = 0
                $res = @()
                $history | ForEach-Object {
                    if ($_ -like '-*') {
                        $res += $_i
                    }
                    $_i++
                }
                return $res[0]
            }
            $i = fn $history
            if ($i) {
                $prefix = $history[0..($i - 1)] -join ' '
                $history[$i..($history.Count - 1)] | ForEach-Object {
                    try {
                        $PSCompletions.comp_data.$cmd.$($prefix + ' ' + $_)[-1] = $PSCompletions.comp_data.$($cmd + '_info').num--
                    }
                    catch {}
                }
                $base = $prefix -split ' '
            }
            else {
                $base = $history
            }

            while ($base.Count -gt 1) {
                try {
                    $PSCompletions.comp_data.$cmd.$($base -join ' ')[-1] = $PSCompletions.comp_data.$($cmd + '_info').num--
                }
                catch {}
                $base = $base[0..($base.Count - 2)]
            }
        }
        catch {}

        $json_order = (Get-Content -Raw -Path ($PSScriptRoots + '/lang/' + $PSCompletions.lang + '.json') -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { $_ -notin $PSCompletions.comp_data.$($cmd + '_info').exclude }  | Sort-Object {
            try { $PSCompletions.comp_data.$cmd.$($cmd + ' ' + $_)[-1] }catch { 999999 }
        }
        $path_order = $PSScriptRoots + '/order.json'
        $order_old = (Get-Content -Raw -Path ($path_order) | ConvertFrom-Json).PSObject.Properties.Name

        if (($json_order -join ' ') -ne ($order_old -join ' ')) {
            $i = 1
            $order = [ordered]@{}
            $json_order | ForEach-Object {
                $order.$_ = $i
                $i++
            }
            $order | ConvertTo-Json | Out-File $path_order -Force
        }
    }  -ArgumentList $PSCompletions, $root_cmd, $PSScriptRoots, (Get-PSReadLineOption).HistorySavePath
}
