function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    function addCompletion($name, $tip = ' ', $symbol = '') {
        $completions.Add(@{
                name   = $name
                symbol = $symbol
                tip    = $tip
            })
    }
    $voltaBinDir = Split-Path (Get-Command volta).Source -Parent
    $toolsDir = "$(Split-Path $voltaBinDir -Parent)\tools\image"
    $list = @("node", "npm", "pnpm", "yarn")

    foreach ($l in $list) {
        $versionList = Get-ChildItem "$toolsDir\$l" -Directory
        foreach ($v in $versionList) {
            addCompletion "pin $l@$($v.BaseName)" "pin - $l@$($v.BaseName)"
        }
    }
    return $completions
}
