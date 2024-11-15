function handleCompletions($completions) {
    $voltaBinDir = Split-Path (Get-Command volta).Source -Parent
    $toolsDir = "$(Split-Path $voltaBinDir -Parent)\tools\image"
    $list = @("node", "npm", "pnpm", "yarn")

    foreach ($l in $list) {
        $versionList = Get-ChildItem "$toolsDir\$l" -Directory
        foreach ($v in $versionList) {
            $completions += $PSCompletions.return_completion("pin $l@$($v.BaseName)", "pin - $l@$($v.BaseName)")
        }
    }
    return $completions
}
