function handleCompletions($completions) {
    $tempList = @()
    function returnCompletion($name, $tip = ' ', $symbol = '') {
        $symbols = foreach ($c in ($symbol -split ' ')) { $PSCompletions.config."symbol_$($c)" }
        $symbols = $symbols -join ''
        $padSymbols = if ($symbols) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbols)" }else { '' }
        $cmd_arr = $name -split ' '

        @{
            name           = $name
            ListItemText   = "$($cmd_arr[-1])$($padSymbols)"
            CompletionText = $cmd_arr[-1]
            ToolTip        = $tip
        }
    }

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
            $tempList += returnCompletion "~ -d $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            $tempList += returnCompletion "-d $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            $tempList += returnCompletion "~ --distribution $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            $tempList += returnCompletion "--distribution $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')

            $tempList += returnCompletion "-s $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--distribution')
            $tempList += returnCompletion "--set-default $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--set-default')

            $tempList += returnCompletion "-t $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--set-default')
            $tempList += returnCompletion "--terminate $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--terminate')

            $tempList += returnCompletion "--unregister $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--unregister')

            $tempList += returnCompletion "--export $($Distro)" $PSCompletions.replace_content($PSCompletions.data.wsl.info.tip.'--export')
        }
    }
    return $tempList + $completions
}
