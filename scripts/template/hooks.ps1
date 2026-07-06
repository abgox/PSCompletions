# Refer to: https://pscompletions.abgox.com/docs/completion/hooks
function handleCompletions($completions) {
    $list = @()

    # $list += $PSCompletions.return_completion('example', "It is from hooks.ps1")

    return $list + $completions
}
