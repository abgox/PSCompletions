function handleCompletions($completions) {
    $tempList = @()

    function CleanNul($data) {
        $res = [System.Collections.Generic.List[byte]]::new()
        foreach ($_ in [System.Text.Encoding]::UTF8.GetBytes($data)) {
            # Remove NUL(0x00) characters from binary data
            if ($_ -ne 0x00) { $res.add($_) }
        }
        return [System.Text.Encoding]::UTF8.GetString($res)
    }

    foreach ($_ in wsl -l -q) {
        $Distro = CleanNul $_
        if ($Distro -ne '') {
            $tempList += $PSCompletions.return_completion("~ -d $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--distribution'))
            $tempList += $PSCompletions.return_completion("-d $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--distribution'))
            $tempList += $PSCompletions.return_completion("~ --distribution $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--distribution'))
            $tempList += $PSCompletions.return_completion("--distribution $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--distribution'))

            $tempList += $PSCompletions.return_completion("-s $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--distribution'))
            $tempList += $PSCompletions.return_completion("--set-default $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--set-default'))

            $tempList += $PSCompletions.return_completion("-t $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--set-default'))
            $tempList += $PSCompletions.return_completion("--terminate $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--terminate'))

            $tempList += $PSCompletions.return_completion("--unregister $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--unregister'))

            $tempList += $PSCompletions.return_completion("--export $($Distro)", $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.'--export'))
        }
    }
    return $tempList + $completions
}
