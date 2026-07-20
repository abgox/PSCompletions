function handleCompletions($completions) {
    if ($PSCompletions.pending.text -like '-*') {
        return $completions
    }
    try {
        $config = scoop config
    }
    catch {
        return $completions
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $tokens = @($PSCompletions.tokens)
    # $tokens_text = @($tokens.text)
    # $cmds = @($tokens | Where-Object type -EQ 'command')
    # $cmds_text = @($cmds.text)
    # $opts = @($tokens | Where-Object type -EQ 'option')
    # $opts_text = @($opts.text)
    $unknown = @($tokens | Where-Object type -EQ 'unknown')
    $unknown_text = @($unknown.text)
    # function add {
    #     param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
    #     if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text)*"))) { return }
    #     $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    # }

    function add2 {
        param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
        if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text -replace '.+[/\\]', '')*"))) { return }
        $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    }

    $root_path = $env:SCOOP, $config.root_path | Select-Object -First 1
    if (-not $root_path) {
        throw $PSCompletions.replace_content($PSCompletions.completions.'scoop-update'.info.tip.warning.config)
    }

    $global_path = $env:SCOOP_GLOBAL, $config.global_path | Select-Object -First 1
    $apps_dir = "$root_path\apps", "$global_path\apps" | Where-Object { Test-Path -LiteralPath $_ }
    # $buckets_dir = "$root_path\buckets"

    $apps_dir | ForEach-Object {
        Get-ChildItem $_ | ForEach-Object {
            $app = $_.Name
            $path = $_.FullName
            if ($app -in $unknown_text) { return }
            $manifest_json = $path + '\current\manifest.json'
            $install_json = $path + '\current\install.json'
            $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json;
`$i = Get-Content -Raw "$install_json" -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json;
`$b = `$i.bucket;
if (`$b) { 'bucket:   ' + `$b; "`n" };
`$v = "$root_path\buckets\`$b\bucket\$($app[0])\$($app.Split('.', 2)[0])\$app.json", "$root_path\buckets\`$b\bucket\$app.json" |
ForEach-Object { (Get-Content `$_ -Raw -Encoding utf8 -ErrorAction Ignore | ConvertFrom-Json).version } |
Select-Object -First 1;
`$new = if (`$v -and `$v -ne `$c.version) { " (`$v)" } else { '' };
'version:  ' + `$c.version + `$new; "`n";
`$category = if (`$c.psmodule) { 'psmodule' } elseif(`$c.font) { 'font' } else { `$null };
if (`$category) { 'category: ' + `$category; "`n" };
'homepage: ' + `$c.homepage; "`n";
`$persistence = @()
if (`$c.link -or `$c.pre_install -match '(?<!#.*)A-New-Link(File|Directory)') { `$persistence += 'link'; }
if (`$c.persist) { `$persistence += 'persist'; }
if (`$persistence) { 'persistence: ' + (`$persistence -join ', '); "`n"; }
if (`$c.admin){ 'permissions: admin'; "`n"; }
if (`$c.description) {
    '-----'; "`n";
    `$c.description.Replace(' | ', "`n")
};
}}
"@
            add2 $app $tip @('continue')
        }
    }

    return $list + $completions
}
