# Refer to: https://pscompletions.abgox.com/docs/completion/hooks
function handleCompletions($completions) {
    $list = @()

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude option parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    $CN = $PSUICulture -like 'zh*'

    switch ($first_item) {
        # Commands that expect a servicename
        {
            $_ -in @(
                'install', 'edit', 'dump',
                'start', 'stop', 'restart',
                'status', 'statuscode',
                'rotate', 'processes', 'remove'
            )
        } {
            if ($filter_input_arr.Count -eq 1) {
                foreach ($svc in (Get-Service)) {
                    $status = $svc.Status.ToString()
                    $display = $svc.DisplayName
                    $tip = if ($CN) {
                        "显示名称: $display`n状态: $status"
                    }
                    else {
                        "DisplayName: $display`nStatus: $status"
                    }
                    $list += $PSCompletions.return_completion($svc.Name, $tip)
                }
            }
        }
        # Commands that expect a servicename then a parameter
        'get' {
            if ($filter_input_arr.Count -eq 1) {
                foreach ($svc in (Get-Service)) {
                    $status = $svc.Status.ToString()
                    $tip = if ($CN) {
                        "查询服务参数`n显示名称: $($svc.DisplayName)`n状态: $status"
                    }
                    else {
                        "Query service parameter`nDisplayName: $($svc.DisplayName)`nStatus: $status"
                    }
                    $list += $PSCompletions.return_completion($svc.Name, $tip)
                }
            }
        }
        'set' {
            if ($filter_input_arr.Count -eq 1) {
                foreach ($svc in (Get-Service)) {
                    $status = $svc.Status.ToString()
                    $tip = if ($CN) {
                        "设置服务参数`n显示名称: $($svc.DisplayName)`n状态: $status"
                    }
                    else {
                        "Set service parameter`nDisplayName: $($svc.DisplayName)`nStatus: $status"
                    }
                    $list += $PSCompletions.return_completion($svc.Name, $tip)
                }
            }
        }
        'reset' {
            if ($filter_input_arr.Count -eq 1) {
                foreach ($svc in (Get-Service)) {
                    $status = $svc.Status.ToString()
                    $tip = if ($CN) {
                        "重置服务参数`n显示名称: $($svc.DisplayName)`n状态: $status"
                    }
                    else {
                        "Reset service parameter`nDisplayName: $($svc.DisplayName)`nStatus: $status"
                    }
                    $list += $PSCompletions.return_completion($svc.Name, $tip)
                }
            }
        }
    }

    return $list + $completions
}
