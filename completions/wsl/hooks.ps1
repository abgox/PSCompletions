function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    function addCompletion($name, $tip = ' ', $symbol = '') {
        $completions.Add(@{
                name   = $name
                symbol = $symbol
                tip    = $tip
            })
    }
    function CleanNul($data) {
        $res = [System.Collections.Generic.List[byte]]::new()
        foreach ($_ in [System.Text.Encoding]::UTF8.GetBytes($data)) {
            # Remove NUL(0x00) characters from binary data
            if ($_ -ne 0x00) { $res.add($_) }
        }
        return [System.Text.Encoding]::UTF8.GetString($res)
    }

    $Distro_list = foreach ($_ in wsl -l -q) { CleanNul $_ }
    foreach ($_ in $Distro_list) {
        if ($_ -ne '') {
            $Distro = $_
            addCompletion "~ -d $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            addCompletion "-d $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            addCompletion "~ --distribution $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            addCompletion "--distribution $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')

            addCompletion "-s $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            addCompletion "--set-default $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--set-default')

            addCompletion "-t $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--set-default')
            addCompletion "--terminate $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--terminate')

            addCompletion "--unregister $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--unregister')

            addCompletion "--export $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--export')
        }
    }
    return $completions
}
