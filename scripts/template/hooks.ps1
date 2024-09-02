function handleCompletions($completions) {
    $tempList = @()
    <#
    Add your code here
    Example:
        $tempList += $PSCompletions.return_completion("rm test", "test")
    #>

    return $tempList + $completions
}
