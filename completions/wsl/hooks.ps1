function handleCompletions($completions) {
    $list = @()

    function CleanNul($data) {
        $res = [System.Collections.Generic.List[byte]]::new()
        foreach ($_ in [System.Text.Encoding]::UTF8.GetBytes($data)) {
            # Remove NUL(0x00) characters from binary data
            if ($_ -ne 0x00) { $res.add($_) }
        }
        return [System.Text.Encoding]::UTF8.GetString($res)
    }


    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude options parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    switch ($last_item) {
        { $_ -in @('-d', '--distribution') } {
            foreach ($_ in wsl -l -q) {
                $Distro = CleanNul $_
                if ($Distro -ne '') {
                    $list += $PSCompletions.return_completion($Distro, $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--distribution'))
                }
            }
        }
        { $_ -in @('-s', '--set-default') } {
            foreach ($_ in wsl -l -q) {
                $Distro = CleanNul $_
                if ($Distro -ne '') {
                    $list += $PSCompletions.return_completion($Distro, $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--set-default'))
                }
            }
        }
        { $_ -in @('-t', '--terminate') } {
            foreach ($_ in wsl -l -q) {
                $Distro = CleanNul $_
                if ($Distro -ne '') {
                    $list += $PSCompletions.return_completion($Distro, $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--terminate'))
                }
            }
        }

        '--unregister' {
            foreach ($_ in wsl -l -q) {
                $Distro = CleanNul $_
                if ($Distro -ne '') {
                    $list += $PSCompletions.return_completion($Distro, $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--unregister'))
                }
            }
        }
        '--export' {
            foreach ($_ in wsl -l -q) {
                $Distro = CleanNul $_
                if ($Distro -ne '') {
                    $list += $PSCompletions.return_completion($Distro, $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--export'))
                }
            }
        }
    }
    return $list + $completions
}
