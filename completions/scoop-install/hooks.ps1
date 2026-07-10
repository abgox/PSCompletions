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

    if ($tokens[-1].text -in '-a', '--arch') {
        return $completions
    }

    $root_path = $env:SCOOP, $config.root_path | Select-Object -First 1
    if (-not $root_path) {
        throw $PSCompletions.replace_content($PSCompletions.completions.'scoop-install'.info.tip.warning.config)
    }
    $global_path = $env:SCOOP_GLOBAL, $config.global_path | Select-Object -First 1
    $apps_dir = "$root_path\apps", "$global_path\apps" | Where-Object { Test-Path $_ }
    $buckets_dir = "$root_path\buckets"

    $PSCompletions.temp_scoop_installed_apps = $apps_dir | ForEach-Object { Get-ChildItem $_ | ForEach-Object { $_.BaseName } }
    $exclude_buckets = $PSCompletions.config.comp_config.scoop.exclude_buckets -split '\|'
    $dir = Get-ChildItem $buckets_dir | ForEach-Object {
        if ($_.Name -in $exclude_buckets) {
            return
        }
        @{
            bucket = $_.BaseName
            path   = "$($_.FullName)\bucket"
        }
    }
    $_ = $PSCompletions.handle_data_by_runspace($dir, {
            param ($items, $PSCompletions, $Host_UI)
            $return = @()
            $tokens_text = $PSCompletions.tokens.text
            foreach ($item in $items) {
                Get-ChildItem $item.path -Recurse -File -Filter *.json | ForEach-Object {
                    if ($_.BaseName -eq 'scoop' -or $_.BaseName -in $PSCompletions.temp_scoop_installed_apps -or ($PSCompletions.pending.text -and $_.BaseName -notlike "$($PSCompletions.pending.text)*")) { return }
                    $app = "$($item.bucket)/$($_.BaseName)"
                    if ($app -in $tokens_text) { return }
                    if ($PSCompletions.config.comp_config[$PSCompletions.cmd].enable_hooks_tip -eq 0) {
                        $tip = ''
                    }
                    else {
                        $manifest_json = $_.FullName
                        $tip = @"
{{
`$c = Get-Content -Raw "$manifest_json" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json;
'version:  ' + `$c.version; "`n";
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
                    }
                    $return += @{
                        ListItemText   = $app
                        CompletionText = $app
                        symbols        = @('SpaceTab')
                        ToolTip        = $tip
                    }
                }
            }
            return $return
        }, {
            param($results)
            return $results
        })
    if ($_) { $list.AddRange($_) }

    return $list + $completions
}
