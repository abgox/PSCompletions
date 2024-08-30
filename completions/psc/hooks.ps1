function handleCompletions($completions) {
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
    foreach ($completion in $PSCompletions.data.list) {

        $completions += returnCompletion "rm $($completion)" $PSCompletions.replace_content($PSCompletions.info.rm.tip)

        $completions += returnCompletion "which $($completion)" $PSCompletions.replace_content($PSCompletions.info.which.tip)

        $completions += returnCompletion "alias add $($completion)" $PSCompletions.replace_content($PSCompletions.info.alias.add.tip)


        $completions += returnCompletion "alias rm $($completion)" $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip) 'SpaceTab'

        foreach ($alias in $PSCompletions.data.alias.$completion) {
            $completions += returnCompletion "alias rm $($completion) $($alias)" $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip_v)
        }

        $completions += returnCompletion "completion $($completion)" $PSCompletions.replace_content($PSCompletions.info.completion.tip) 'SpaceTab'
        $completions += returnCompletion "completion $($completion) language" $PSCompletions.replace_content($PSCompletions.info.completion.language.tip) 'SpaceTab'
        $completions += returnCompletion "completion $($completion) menu_show_tip" $PSCompletions.replace_content($PSCompletions.info.completion.menu_show_tip.tip) 'SpaceTab'

        $completions += returnCompletion "completion $($completion) menu_show_tip 1" $PSCompletions.replace_content($PSCompletions.info.completion.menu_show_tip.tip_v1)
        $completions += returnCompletion "completion $($completion) menu_show_tip 0" $PSCompletions.replace_content($PSCompletions.info.completion.menu_show_tip.tip_v0)

        $language = $PSCompletions.get_language($completion)
        $config = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/config.json") | ConvertFrom-Json
        $json = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/language/$($language).json") | ConvertFrom-Json

        foreach ($language in $config.language) {
            $completions += returnCompletion "completion $($completion) language $($language)" $PSCompletions.replace_content($PSCompletions.info.completion.language.tip_v)
        }
        foreach ($c in $json.config) {
            $tip = $PSCompletions.replace_content($c.tip) -replace '<\@\w+>', ''
            if ($c.values) {
                $completions += returnCompletion "completion $($completion) $($c.name)" $tip 'SpaceTab'
                foreach ($value in $c.values) {
                    $completions += returnCompletion "completion $($completion) $($c.name) $($value)" $PSCompletions.replace_content($PSCompletions.info.completion.tip_v)
                }
            }
            else {
                $completions += returnCompletion "completion $($completion) $($c.name)" $tip
            }
            $config_item = $c.name
            $completions += returnCompletion "reset completion $($completion) $($config_item)" $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip_v)
        }

        $completions += returnCompletion "reset alias $($completion)" $PSCompletions.replace_content($PSCompletions.info.reset.alias.tip)


        $symbol = if ($json.config) { 'SpaceTab' }else { '' }
        $completions += returnCompletion "reset completion $($completion)" $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip) $symbol
    }

    foreach ($completion in $PSCompletions.list) {
        if ($completion -notin $PSCompletions.data.list) {
            $completions += returnCompletion "add $($completion)" $PSCompletions.replace_content($PSCompletions.info.add.tip)
        }
    }

    foreach ($completion in $PSCompletions.update) {
        $completions += returnCompletion "update $($completion)" $PSCompletions.replace_content($PSCompletions.info.update.tip)
    }

    foreach ($item in $PSCompletions.menu.const.color_item) {
        foreach ($color in $PSCompletions.menu.const.color_value) {
            $completions += returnCompletion "menu custom color $($item) $($color)" $PSCompletions.replace_content($PSCompletions.info.menu.custom.color.tip)
        }
    }
    return $completions
}
