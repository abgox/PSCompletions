function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    function addCompletion($name, $symbol = '', $tip = ' ') {
        $completions.Add(@{
                name   = $name
                symbol = $symbol
                tip    = $tip
            })
    }

    # Add your code here

    return $completions
}
