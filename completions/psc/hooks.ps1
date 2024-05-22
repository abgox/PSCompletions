function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    function addCompletion($name, $symbol = '', $tip = ' ') {
        $completions.Add(@{
                name   = $name
                symbol = $symbol
                tip    = $tip
            })
    }
    foreach ($completion in $PSCompletions.cmd.Keys) {

        addCompletion "rm $($completion)" '' $PSCompletions.replace_content($PSCompletions.info.rm.tip)

        addCompletion "which $($completion)" '' $PSCompletions.replace_content($PSCompletions.info.which.tip)

        addCompletion "alias add $($completion)" '' $PSCompletions.replace_content($PSCompletions.info.alias.add.tip)


        addCompletion "alias rm $($completion)" 'SpaceTab' $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip)

        foreach ($alias in $PSCompletions.cmd.$completion) {
            addCompletion "alias rm $($completion) $($alias)" ''  $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip_v)
        }

        addCompletion "completion $($completion)" 'SpaceTab' $PSCompletions.replace_content($PSCompletions.info.completion.tip)
        addCompletion "completion $($completion) language" 'SpaceTab' $PSCompletions.replace_content($PSCompletions.info.completion.language.tip)
        addCompletion "completion $($completion) menu_show_tip" 'SpaceTab' $PSCompletions.replace_content($PSCompletions.info.completion.menu_show_tip.tip)

        addCompletion "completion $($completion) menu_show_tip 1" '' $PSCompletions.replace_content($PSCompletions.info.completion.menu_show_tip.tip_v1)
        addCompletion "completion $($completion) menu_show_tip 0" '' $PSCompletions.replace_content($PSCompletions.info.completion.menu_show_tip.tip_v0)

        $language = $PSCompletions.get_language($completion)
        $config = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/config.json") | ConvertFrom-Json
        $json = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/language/$($language).json") | ConvertFrom-Json

        foreach ($language in $config.language) {
            addCompletion  "completion $($completion) language $($language)" '' $PSCompletions.replace_content($PSCompletions.info.completion.language.tip_v)
        }
        foreach ($c in $json.config) {
            $tip = $PSCompletions.replace_content($c.tip) -replace '<\@\w+>', ''
            if ($c.values) {
                addCompletion "completion $($completion) $($c.name)" 'SpaceTab' $tip
                foreach ($value in $c.values) {
                    addCompletion "completion $($completion) $($c.name) $($value)" '' $PSCompletions.replace_content($PSCompletions.info.completion.tip_v)
                }
            }
            else {
                addCompletion "completion $($completion) $($c.name)" '' $tip
            }
            $config_item = $c.name
            addCompletion "reset completion $($completion) $($config_item)" '' $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip_v)
        }

        addCompletion "reset alias $($completion)" '' $PSCompletions.replace_content($PSCompletions.info.reset.alias.tip)


        $symbol = if ($json.config) { 'SpaceTab' }else { '' }
        addCompletion "reset completion $($completion)" $symbol $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip)
    }

    foreach ($completion in $PSCompletions.list) {
        if ($completion -notin $PSCompletions.cmd.Keys) {
            addCompletion "add $($completion)" '' $PSCompletions.replace_content($PSCompletions.info.add.tip)
        }
    }

    foreach ($completion in $PSCompletions.update) {
        addCompletion "update $($completion)" '' $PSCompletions.replace_content($PSCompletions.info.update.tip)
    }

    foreach ($item in $PSCompletions.menu.const.color_item) {
        foreach ($color in $PSCompletions.menu.const.color_value) {
            addCompletion "menu custom color $($item) $($color)" '' $PSCompletions.replace_content($PSCompletions.info.menu.custom.color.tip)
        }
    }
    return $completions
}
