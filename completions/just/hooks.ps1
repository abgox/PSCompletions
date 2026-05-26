function handleCompletions($completions) {
    $list = @()

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr
    $last_item = $filter_input_arr[-1]

    function return_recipes {
        $recipes = just --summary 2>$null | ForEach-Object {
            $_.Split(' ')
        }
        return $recipes
    }

    if (!$last_item) {
        $recipes = return_recipes
        foreach ($recipe in $recipes) {
            $list += $PSCompletions.return_completion($recipe)
        }
    }

    return $list + $completions
}
