function handleCompletions($completions) {
    foreach ($completion in $PSCompletions.data.list) {

        $completions += $PSCompletions.return_completion("rm $($completion)", $PSCompletions.replace_content($PSCompletions.info.rm.tip))

        $completions += $PSCompletions.return_completion("which $($completion)", $PSCompletions.replace_content($PSCompletions.info.which.tip))

        $completions += $PSCompletions.return_completion("alias add $($completion)", $PSCompletions.replace_content($PSCompletions.info.alias.add.tip))


        $completions += $PSCompletions.return_completion("alias rm $($completion)", $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip), 'SpaceTab')

        foreach ($alias in $PSCompletions.data.alias.$completion) {
            $completions += $PSCompletions.return_completion("alias rm $($completion) $($alias)", $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip_v))
        }

        $completions += $PSCompletions.return_completion("completion $($completion)", $PSCompletions.replace_content($PSCompletions.info.completion.tip), 'SpaceTab')
        $completions += $PSCompletions.return_completion("completion $($completion) language", $PSCompletions.replace_content($PSCompletions.info.completion.language.tip), 'SpaceTab')
        $completions += $PSCompletions.return_completion("completion $($completion) enable_tip", $PSCompletions.replace_content($PSCompletions.info.completion.enable_tip.tip), 'SpaceTab')

        $completions += $PSCompletions.return_completion("completion $($completion) enable_tip 1", $PSCompletions.replace_content($PSCompletions.info.completion.enable_tip.tip_v1))
        $completions += $PSCompletions.return_completion("completion $($completion) enable_tip 0", $PSCompletions.replace_content($PSCompletions.info.completion.enable_tip.tip_v0))

        $language = $PSCompletions.get_language($completion)
        $config = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/config.json") | ConvertFrom-Json
        $json = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/language/$($language).json") | ConvertFrom-Json

        foreach ($language in $config.language) {
            $completions += $PSCompletions.return_completion("completion $($completion) language $($language)", $PSCompletions.replace_content($PSCompletions.info.completion.language.tip_v))
        }
        foreach ($c in $json.config) {
            $tip = $PSCompletions.replace_content($c.tip) -replace '<\@\w+>', ''
            if ($c.values) {
                $completions += $PSCompletions.return_completion("completion $($completion) $($c.name)", $tip, 'SpaceTab')
                foreach ($value in $c.values) {
                    $completions += $PSCompletions.return_completion("completion $($completion) $($c.name) $($value)", $PSCompletions.replace_content($PSCompletions.info.completion.tip_v))
                }
            }
            else {
                $completions += $PSCompletions.return_completion("completion $($completion) $($c.name)", $tip)
            }
            $config_item = $c.name
            $completions += $PSCompletions.return_completion("reset completion $($completion) $($config_item)", $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip_v))
        }

        $completions += $PSCompletions.return_completion("reset alias $($completion)", $PSCompletions.replace_content($PSCompletions.info.reset.alias.tip))


        $symbol = if ($json.config) { 'SpaceTab' }else { '' }
        $completions += $PSCompletions.return_completion("reset completion $($completion)", $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip), $symbol)
    }

    foreach ($completion in $PSCompletions.list) {
        if ($completion -notin $PSCompletions.data.list) {
            $completions += $PSCompletions.return_completion("add $($completion)", $PSCompletions.replace_content($PSCompletions.info.add.tip))
        }
    }

    foreach ($completion in $PSCompletions.update) {
        $completions += $PSCompletions.return_completion("update $($completion)", $PSCompletions.replace_content($PSCompletions.info.update.tip))
    }

    foreach ($item in $PSCompletions.menu.const.color_item) {
        foreach ($color in $PSCompletions.menu.const.color_value) {
            $completions += $PSCompletions.return_completion("menu custom color $($item) $($color)", $PSCompletions.replace_content($PSCompletions.info.menu.custom.color.tip))
        }
    }
    return $completions
}
