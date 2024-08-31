function handleCompletions($completions) {
    function returnCompletion($name, $tip = ' ', $symbol = '') {
        $symbols = foreach ($c in ($symbol -split ' ')) { $PSCompletions.config.$c }
        $symbols = $symbols -join ''
        $padSymbols = if ($symbols) { "$($PSCompletions.config.between_item_and_symbol)$($symbols)" }else { '' }
        $cmd_arr = $name -split ' '

        @{
            name           = $name
            ListItemText   = "$($cmd_arr[-1])$($padSymbols)"
            CompletionText = $cmd_arr[-1]
            ToolTip        = $tip
        }
    }
    $voltaBinDir = Split-Path (Get-Command volta).Source -Parent
    $toolsDir = "$(Split-Path $voltaBinDir -Parent)\tools\image"
    $list = @("node", "npm", "pnpm", "yarn")

    foreach ($l in $list) {
        $versionList = Get-ChildItem "$toolsDir\$l" -Directory
        foreach ($v in $versionList) {
            $completions += returnCompletion "pin $l@$($v.BaseName)" "pin - $l@$($v.BaseName)"
        }
    }
    return $completions
}
