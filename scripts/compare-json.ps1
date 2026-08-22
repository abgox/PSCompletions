#Requires -Version 7.0

param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [array]$CompletionList,
    [ArgumentCompletions('en-US', 'zh-CN')]
    [string]$BaseLang,
    [switch]$All,
    [switch]$Json
)

Set-StrictMode -Off

. $PSScriptRoot\utils.ps1

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path -LiteralPath $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) { . $PSScriptRoot\..\module\PSCompletions\PSCompletions.ps1 }
$PSCompletions.initialize($true)

$text = $text.'compare-json'

function outText {
    param($text)
    if ($text -is [array]) { $text = $text -join "`n" }
    $PSCompletions.write_with_color($PSCompletions.replace_content($text))
}

if (-not $BaseLang) { $BaseLang = 'en-US' }
if (-not $CompletionList) {
    if ($All) {
        $CompletionList = (Get-ChildItem "$PSScriptRoot\..\completions" -Directory).Name
    }
    else {
        $CompletionList = Get-RecentCompletions -CompletionsDir "$PSScriptRoot\..\completions"
        if ($CompletionList.Count -eq 0) {
            outText $text.noRecent
            return
        }
    }
}

function Get-ValueType {
    param($Value)
    if ($null -eq $Value) { return 'Null' }
    if ($Value -is [array]) { return 'Array' }
    if ($Value -is [System.Collections.IDictionary]) { return 'Hashtable' }
    return $Value.GetType().Name
}

function Compare-Lang {
    param (
        [string]$baseJson,
        [string]$targetJson,
        [string]$targetLang
    )

    $baseContent = Get-Content -Path $baseJson -Raw | ConvertFrom-Json -AsHashtable
    $targetContent = Get-Content -Path $targetJson -Raw | ConvertFrom-Json -AsHashtable

    $stats = @{
        totalTips          = 0
        translatedTips     = 0
        missingInTarget    = @()
        extraInTarget      = @()
        typeMismatch       = @()
        semanticMismatch   = @()
        valueDiff          = @()
        untranslated       = @()
        duplicateItems     = @()
        meaninglessUsage   = @()
        missingUsage       = @()
        duplicateOptions   = @()
        usageOrder         = @()
        usageTooSimple     = @()
        usageSeparator     = @()
        optionMissingNext  = @()
        forbiddenEmptyNext = @()
        usageRootPrefix    = @()
    }

    function Normalize-Value {
        param($Value, [string]$Key = '')

        if ($null -eq $Value) { return }
        if ($Value -is [System.Collections.IDictionary]) {
            if ($Value.ContainsKey('name') -and $Key -in 'next', 'option', 'global_option', 'alias') {
                return , @($Value)
            }
            if ($Key -eq 'alias' -and $Value.Count -eq 0) {
                return , @()
            }
        }
        if ($Value -is [string] -and $Key -eq 'alias') {
            return , @($Value)
        }
        if ($Value -is [array] -and $Value.Count -eq 0) {
            return , $Value
        }
        return $Value
    }

    function Test-NamedObjectArray {
        param([array]$ArrA, [array]$ArrB)
        foreach ($arr in @($ArrA, $ArrB)) {
            if ($arr.Count -gt 0 -and $arr[0] -is [System.Collections.IDictionary] -and $arr[0].ContainsKey('name')) {
                return $true
            }
        }
        return $false
    }

    function Test-Duplicates {
        param([array]$Arr, [string]$Path, [string]$Side)

        if ($null -eq $Arr -or $Arr.Count -lt 2) { return }

        $sideLabel = if ($Side -eq 'base') { $BaseLang } else { $targetLang }
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

        foreach ($item in $Arr) {
            if ($item -isnot [System.Collections.IDictionary]) { continue }
            $n = $item.name
            if ($null -eq $n) { continue }
            if (-not $seen.Add([string]$n)) {
                $currentPath = if ($Path) { "$Path > $n" } else { "$n" }
                $suffix = " (<@Red>$sideLabel<@Cyan>)"
                $stats.duplicateItems += @{ path = "$currentPath$suffix"; name = $currentPath }
            }
        }
    }

    function Compare-TranslatableText {
        param($BaseVal, $TargetVal, [string]$Path, [bool]$IdenticalOk = $false)

        # Note: `$x = if (c) { @($v) }` flattens a single-element array to a scalar
        $baseArr = @()
        if ($null -ne $BaseVal) { $baseArr = @($BaseVal) }
        $targetArr = @()
        if ($null -ne $TargetVal) { $targetArr = @($TargetVal) }

        if ($baseArr.Count -eq 0 -and $targetArr.Count -eq 0) { return }
        if ($baseArr.Count -eq 0) {
            # base (e.g. en-US) has nothing but target has content — also a one-sided difference
            if ($targetArr.Count -gt 0) {
                $stats.extraInTarget += @{ path = $Path; name = $Path }
            }
            return
        }

        $stats.totalTips++

        if ($targetArr.Count -eq 0) {
            $stats.missingInTarget += @{ path = $Path; name = $Path }
            return
        }

        # usage/example may mix {cmd, desc} objects and plain strings: check each item's structure
        $hasObject = $false
        foreach ($item in $baseArr) {
            if ($item -is [System.Collections.IDictionary]) { $hasObject = $true; break }
        }
        if (-not $hasObject) {
            foreach ($item in $targetArr) {
                if ($item -is [System.Collections.IDictionary]) { $hasObject = $true; break }
            }
        }
        if ($hasObject) {
            $allDescTranslated = $true
            if ($baseArr.Count -ne $targetArr.Count) {
                $stats.semanticMismatch += @{
                    path   = $Path
                    name   = $Path
                    reason = [string]::Format($text.reasonCount, $BaseLang, $baseArr.Count, $targetLang, $targetArr.Count)
                }
            }
            $max = [Math]::Min($baseArr.Count, $targetArr.Count)
            for ($i = 0; $i -lt $max; $i++) {
                $b = $baseArr[$i]
                $t = $targetArr[$i]
                $bObj = $b -is [System.Collections.IDictionary]
                $tObj = $t -is [System.Collections.IDictionary]
                if ($bObj -ne $tObj) {
                    $stats.semanticMismatch += @{
                        path   = "$Path > item $i"
                        name   = $Path
                        reason = [string]::Format($text.reasonType, $i)
                    }
                    continue
                }
                if ($bObj) {
                    foreach ($f in 'cmd', 'desc') {
                        if (($null -ne $b[$f]) -ne ($null -ne $t[$f])) {
                            $stats.semanticMismatch += @{
                                path   = "$Path > item $i"
                                name   = $Path
                                reason = [string]::Format($text.reasonMissingField, $i, $f)
                            }
                        }
                    }
                    $bCmd = $b['cmd']
                    $tCmd = $t['cmd']
                    if ($null -notin $bCmd, $tCmd -and ([string]$bCmd).Trim() -ne ([string]$tCmd).Trim()) {
                        $stats.semanticMismatch += @{
                            path   = "$Path > item $i"
                            name   = $Path
                            reason = [string]::Format($text.reasonCmdValue, $i, $bCmd, $tCmd)
                        }
                    }
                    $bDesc = $b['desc']
                    $tDesc = $t['desc']
                    if ($null -ne $bDesc -and $null -ne $tDesc) {
                        $bs = ([string]$bDesc).Trim()
                        $ts = ([string]$tDesc).Trim()
                        $isTemplate = $bs -like '{{*}}' -and $ts -like '{{*}}' -and $bs -eq $ts
                        if (-not $isTemplate -and $bs -eq $ts) {
                            $allDescTranslated = $false
                            $stats.untranslated += @{ path = "$Path > item $i > desc"; name = $Path }
                        }
                    }
                }
            }
            if ($allDescTranslated) { $stats.translatedTips++ }
            return
        }

        foreach ($item in $baseArr) {
            if ($item -isnot [string]) { return }
        }
        foreach ($item in $targetArr) {
            if ($item -isnot [string]) { return }
        }

        $baseStr = $baseArr -join ''
        $targetStr = $targetArr -join ''

        $isTemplate = $targetStr -like '{{*}}' -and $baseStr -like '{{*}}' -and $targetStr -eq $baseStr
        if ($isTemplate -or $targetStr -ne $baseStr -or $IdenticalOk) {
            $stats.translatedTips++
        }
        else {
            $stats.untranslated += @{ path = $Path; name = $Path }
        }
    }

    function Compare-Value {
        param($BaseVal, $TargetVal, [string]$Path, [string]$Key, [bool]$SkipValueCheck)

        if ($Key -in 'tip', 'description', 'usage', 'example') {
            Compare-TranslatableText -BaseVal $BaseVal -TargetVal $TargetVal -Path $Path -IdenticalOk ($Key -in 'usage', 'example')
            return
        }
        $BaseVal = Normalize-Value -Value $BaseVal -Key $Key
        $TargetVal = Normalize-Value -Value $TargetVal -Key $Key

        $baseType = Get-ValueType $BaseVal
        $targetType = Get-ValueType $TargetVal

        if ($baseType -eq 'Null' -and $targetType -eq 'Null') { return }

        if ($baseType -eq 'Null') {
            $stats.extraInTarget += @{ path = "$Path"; name = $Path }
            return
        }
        if ($targetType -eq 'Null') {
            $stats.missingInTarget += @{ path = "$Path"; name = $Path }
            return
        }
        if ($baseType -ne $targetType) {
            if ($baseType -eq 'Array' -or $targetType -eq 'Array' -or $baseType -eq 'Hashtable' -or $targetType -eq 'Hashtable') {
                $suffix = " (<@Red>$baseType<@Cyan> > <@Red>$targetType<@Cyan>)"
                $stats.typeMismatch += @{ path = "$Path$suffix"; name = $Path }
                return
            }
        }
        if ($Key -eq 'next' -and $baseType -ne 'Array' -and $targetType -ne 'Array') {
            if ($BaseVal -eq 0 -or $TargetVal -eq 0) {
                if ($BaseVal -ne $TargetVal) {
                    $stats.semanticMismatch += @{
                        path   = $Path
                        name   = $Path
                        reason = [string]::Format($text.reasonNextValue, $BaseLang, $BaseVal, $targetLang, $TargetVal)
                    }
                }
                return
            }
        }
        if ($baseType -eq 'Array' -or $targetType -eq 'Array') {
            $baseArr = @($BaseVal)
            $targetArr = @($TargetVal)

            Test-Duplicates -Arr $baseArr -Path $Path -Side 'base'
            Test-Duplicates -Arr $targetArr -Path $Path -Side 'target'

            if (Test-NamedObjectArray $baseArr $targetArr) {
                if ($baseType -ne $targetType) {
                    $suffix = " (<@Red>$baseType<@Cyan> > <@Red>$targetType<@Cyan>)"
                    $stats.typeMismatch += @{ path = "$Path$suffix"; name = $Path }
                    return
                }
                Compare-NamedArray -BaseArr $baseArr -TargetArr $targetArr -Path $Path -SkipValueCheck $SkipValueCheck
            }
            else {
                if ($SkipValueCheck) { return }
                foreach ($v in $baseArr) {
                    if ($v -notin $targetArr) { $stats.missingInTarget += @{ path = "$Path > $v"; name = $Path } }
                }
                foreach ($v in $targetArr) {
                    if ($v -notin $baseArr) { $stats.extraInTarget += @{ path = "$Path > $v"; name = $Path } }
                }
            }
            return
        }
        if ($baseType -eq 'Hashtable' -and $targetType -eq 'Hashtable') {
            Compare-Fields -BaseObj $BaseVal -TargetObj $TargetVal -Path $Path -SkipValueCheck $SkipValueCheck
            return
        }
        if ($baseType -ne $targetType) {
            $suffix = " (<@Red>$baseType<@Cyan> > <@Red>$targetType<@Cyan>)"
            $stats.typeMismatch += @{ path = "$Path$suffix"; name = $Path }
            return
        }
        if ($Key -eq 'name') {
            if ($BaseVal -ne $TargetVal) {
                $suffix = " (<@Red>$BaseVal<@Cyan> > <@Red>$TargetVal<@Cyan>)"
                $stats.valueDiff += @{ path = "$Path$suffix"; name = $Path }
            }
            return
        }
        if (-not $SkipValueCheck -and $BaseVal -ne $TargetVal) {
            $suffix = " (<@Red>$BaseVal<@Cyan> > <@Red>$TargetVal<@Cyan>)"
            $stats.valueDiff += @{ path = "$Path$suffix"; name = $Path }
        }
    }

    function Compare-Fields {
        param([hashtable]$BaseObj, [hashtable]$TargetObj, [string]$Path, [bool]$SkipValueCheck = $false)

        # Note: `$x = if (c) { @($v) }` flattens a single-element array to a scalar
        $baseKeys = @()
        if ($BaseObj) { $baseKeys = @($BaseObj.Keys) }
        $targetKeys = @()
        if ($TargetObj) { $targetKeys = @($TargetObj.Keys) }
        $allKeys = @($baseKeys) + @($targetKeys) | Select-Object -Unique

        foreach ($key in $allKeys) {
            if ($Path -eq 'meta' -and $key -eq 'url') { continue }

            $baseVal = $null
            if ($BaseObj -and $BaseObj.ContainsKey($key)) { $baseVal = $BaseObj[$key] }
            $targetVal = $null
            if ($TargetObj -and $TargetObj.ContainsKey($key)) { $targetVal = $TargetObj[$key] }

            $currentPath = if ($Path) { "$Path > $key" } else { $key }
            $childSkip = $SkipValueCheck -or ($CompletionName -eq 'psc' -and $key -ne 'name')

            Compare-Value -BaseVal $baseVal -TargetVal $targetVal -Path $currentPath -Key $key -SkipValueCheck $childSkip
        }
    }

    function Compare-NamedArray {
        param([array]$BaseArr, [array]$TargetArr, [string]$Path, [bool]$SkipValueCheck = $false)

        $targetByName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($item in $TargetArr) { if ($item.name) { $targetByName[$item.name] = $item } }

        $baseByName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($item in $BaseArr) { if ($item.name) { $baseByName[$item.name] = $item } }

        foreach ($baseItem in $BaseArr) {
            $baseName = $baseItem.name
            $currentPath = if ($Path) { "$Path > $baseName" } else { $baseName }

            if ($targetByName.ContainsKey($baseName)) {
                Compare-Fields -BaseObj $baseItem -TargetObj $targetByName[$baseName] -Path $currentPath -SkipValueCheck $SkipValueCheck
            }
            else {
                $stats.missingInTarget += @{ path = $currentPath; name = $baseName }
                foreach ($tKey in @('tip', 'description')) {
                    if ($baseItem.ContainsKey($tKey) -and $null -ne $baseItem[$tKey]) {
                        $arr = @($baseItem[$tKey])
                        if ($arr.Count -gt 0 -and !([string]::IsNullOrEmpty(($arr -join '').Trim()))) {
                            $stats.totalTips++
                        }
                    }
                }
            }
        }
        foreach ($targetItem in $TargetArr) {
            $targetName = $targetItem.name
            if ($targetName -and !$baseByName.ContainsKey($targetName)) {
                $currentPath = if ($Path) { "$Path > $targetName" } else { $targetName }
                $stats.extraInTarget += @{ path = $currentPath; name = $targetName }
            }
        }
    }

    function Validate-UsageFormat {
        param([string]$Line, [string]$Path, [bool]$IsOption)

        $u = $Line.Substring(2).Trim()
        # Leading form block: forms split by comma/pipe, stop at placeholders like '<', '=', '['
        $m = [regex]::Match($u, '^[^\s,|<=\[|]+(?:\s*[,|]\s*[^\s,|<=\[|]+)*')
        if (-not $m.Success) { return }
        $block = $m.Value
        if ($block -notmatch '[,|]') { return }

        $forms = @($block -split '[,|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $hasPipe = $block.Contains('|')
        $hasComma = $block.Contains(',')
        if ($IsOption -and $hasPipe -and -not $hasComma) {
            $stats.usageSeparator += @{ path = $Path; name = $Path }
        }
        elseif (-not $IsOption -and $hasComma -and -not $hasPipe) {
            $stats.usageSeparator += @{ path = $Path; name = $Path }
        }
        for ($i = 0; $i -lt $forms.Count - 1; $i++) {
            if ($forms[$i].Length -gt $forms[$i + 1].Length) {
                $stats.usageOrder += @{ path = $Path; name = $Path }
                break
            }
        }
    }

    function Validate-ItemUsage {
        param([hashtable]$Item, [string]$Path, [bool]$IsOption = $false)

        $hasAlias = $null -ne $Item.alias -and @($Item.alias).Count -gt 0
        $hasNext = $null -ne $Item.next

        $needsUsage = $hasAlias

        $hasUsage = $false
        $useless = $false
        $isOptionLike = $IsOption -or ($Item.name -match '^-')
        if ($null -ne $Item.usage -and @($Item.usage).Count -gt 0) {
            foreach ($u in @($Item.usage)) {
                if ($u -is [string]) {
                    Validate-UsageFormat -Line "U: $u" -Path $Path -IsOption $isOptionLike
                    if (-not $hasUsage) {
                        $hasUsage = $true
                        if ($u.Trim() -eq $Item.name) { $useless = $true }
                    }
                }
                elseif ($u -is [System.Collections.IDictionary]) {
                    $cmd = if ($null -ne $u['cmd']) { [string]$u['cmd'] } else { '' }
                    if ($cmd) {
                        Validate-UsageFormat -Line "U: $cmd" -Path $Path -IsOption $isOptionLike
                        if (-not $hasUsage) {
                            $hasUsage = $true
                            if ($cmd.Trim() -eq $Item.name) { $useless = $true }
                        }
                    }
                }
            }
        }

        if ($needsUsage -and -not $hasUsage) {
            $stats.missingUsage += @{ path = $Path; name = $Item.name }
        }
        elseif ($hasUsage -and $useless) {
            if (-not $hasAlias -and -not $hasNext) {
                $stats.meaninglessUsage += @{ path = $Path; name = $Item.name }
            }
            else {
                $stats.usageTooSimple += @{ path = $Path; name = $Item.name }
            }
        }

        # No next -> the engine treats a value-taking option as a boolean switch (wrong completions).
        # Only options are checked: a subcommand's <...> is its argument, not requiring next.
        # '#' inside a usage line starts a comment: only the part before it counts.
        if ($isOptionLike -and $hasUsage -and -not $hasNext) {
            foreach ($u in @($Item.usage)) {
                $s = if ($u -is [string]) { $u } elseif ($u -is [System.Collections.IDictionary] -and $null -ne $u['cmd']) { [string]$u['cmd'] } else { '' }
                $s = ($s -split '#', 2)[0]
                if ($s -match '<[^<>]*>') {
                    $stats.optionMissingNext += @{ path = $Path; name = $Item.name }
                    break
                }
            }
        }

        # Only deeper items are flagged: root-level usage may legitimately start with the root name.
        if ($Path -match ' > ' -and $hasUsage) {
            foreach ($u in @($Item.usage)) {
                $s = if ($u -is [string]) { $u } elseif ($u -is [System.Collections.IDictionary] -and $null -ne $u['cmd']) { [string]$u['cmd'] } else { '' }
                if ($s.StartsWith("$CompletionName ")) {
                    $stats.usageRootPrefix += @{ path = $Path; name = $Item.name }
                    break
                }
            }
        }
    }

    function Test-SubtreeEqual {
        param($A, $B)

        if ($null -eq $A -and $null -eq $B) { return $true }
        if ($null -eq $A -or $null -eq $B) { return $false }
        if ($A -is [System.Collections.IDictionary] -and $B -is [System.Collections.IDictionary]) {
            if ($A.Count -ne $B.Count) { return $false }
            foreach ($k in $A.Keys) {
                if (-not $B.ContainsKey($k)) { return $false }
                if (-not (Test-SubtreeEqual $A[$k] $B[$k])) { return $false }
            }
            return $true
        }
        if ($A -is [array] -and $B -is [array]) {
            if ($A.Count -ne $B.Count) { return $false }
            for ($i = 0; $i -lt $A.Count; $i++) {
                if (-not (Test-SubtreeEqual $A[$i] $B[$i])) { return $false }
            }
            return $true
        }
        return $A -eq $B
    }

    function Validate-Options {
        param([hashtable]$Content)

        $globalOptions = @()
        if ($Content.global_option) {
            foreach ($opt in @($Content.global_option)) {
                if ($opt.name) {
                    $globalOptions += [pscustomobject]@{ name = $opt.name; opt = $opt }
                }
            }
        }
        if ($globalOptions.Count -eq 0) { return }

        function Test-GlobalDuplicate {
            param([hashtable]$Opt, [string]$Path)

            if ($null -eq $Opt.name) { return }
            foreach ($g in $globalOptions) {
                if ($g.name -eq $Opt.name -and (Test-SubtreeEqual $Opt $g.opt)) {
                    $stats.duplicateOptions += @{ path = "$Path > $($Opt.name)"; name = $Opt.name }
                    return
                }
            }
        }

        function Check-OptionDuplicates {
            param([hashtable]$Node, [string]$Path)

            if ($Node.option) {
                foreach ($opt in @($Node.option)) {
                    Test-GlobalDuplicate -Opt $opt -Path $Path
                }
            }

            if ($Node.next) {
                foreach ($sub in @($Node.next)) {
                    if ($sub.name) {
                        Check-OptionDuplicates -Node $sub -Path "$Path > $($sub.name)"
                    }
                }
            }
        }

        if ($Content.option) {
            foreach ($opt in @($Content.option)) {
                Test-GlobalDuplicate -Opt $opt -Path 'option'
            }
        }

        if ($Content.next) {
            foreach ($sub in @($Content.next)) {
                if ($sub.name) {
                    Check-OptionDuplicates -Node $sub -Path $sub.name
                }
            }
        }
    }

    function Validate-AllTips {
        param([hashtable]$Content, [string]$BasePath, [bool]$IsOption = $false, [bool]$IsCommand = $false)

        if ($Content.name) {
            Validate-ItemUsage -Item $Content -Path $BasePath -IsOption $IsOption
        }

        # Check: command must not have an empty next array
        if ($IsCommand -and $Content.ContainsKey('next') -and $null -ne $Content['next']) {
            $nextVal = $Content['next']
            if ($nextVal -is [array] -and $nextVal.Count -eq 0) {
                $stats.forbiddenEmptyNext += @{ path = $BasePath; name = $Content.name }
            }
        }

        if ($Content.next) {
            foreach ($sub in @($Content.next)) {
                if ($sub -is [hashtable] -and $sub.name) {
                    $subPath = if ($BasePath) { "$BasePath > $($sub.name)" } else { $sub.name }
                    # Items in 'next' array are commands (not options)
                    Validate-AllTips -Content $sub -BasePath $subPath -IsCommand $true
                }
            }
        }

        if ($Content.option) {
            foreach ($opt in @($Content.option)) {
                if ($opt -is [hashtable] -and $opt.name) {
                    $optPath = if ($BasePath) { "$BasePath > option > $($opt.name)" } else { "option > $($opt.name)" }
                    Validate-AllTips -Content $opt -BasePath $optPath -IsOption $true
                }
            }
        }

        if ($Content.global_option) {
            foreach ($opt in @($Content.global_option)) {
                if ($opt -is [hashtable] -and $opt.name) {
                    $optPath = "global_option > $($opt.name)"
                    Validate-AllTips -Content $opt -BasePath $optPath -IsOption $true
                }
            }
        }
    }

    Validate-Options -Content $baseContent
    Validate-AllTips -Content $baseContent -BasePath ''
    Validate-AllTips -Content $targetContent -BasePath ''

    Compare-Fields -BaseObj $baseContent -TargetObj $targetContent -Path ''

    $translationRate = 100
    if ($stats.totalTips -gt 0) {
        $translationRate = [Math]::Round(($stats.translatedTips / $stats.totalTips) * 100, 2)
    }

    return @{
        stats = $stats
        rate  = $translationRate
    }
}

$allResults = @()

foreach ($CompletionName in $CompletionList) {
    if (!$CompletionName.Trim()) {
        outText $text.invalidName
        continue
    }
    $langDir = [System.IO.Path]::Combine($PSScriptRoot, '..', 'completions', $CompletionName, 'language')
    if (!(Test-Path -LiteralPath $langDir)) {
        continue
    }
    $allLangFiles = Get-ChildItem -Path $langDir -Filter '*.json' | ForEach-Object { $_.BaseName }
    $otherLangs = $allLangFiles | Where-Object { $_ -ne $BaseLang } | Sort-Object
    if ($otherLangs.Count -eq 0) {
        continue
    }
    $baseJson = [System.IO.Path]::Combine($langDir, $BaseLang + '.json')
    if (!(Test-Path -LiteralPath $baseJson)) {
        outText $text.invalidLang
        continue
    }
    & $PSScriptRoot\sort-json.ps1 $CompletionName -Quiet

    foreach ($lang in $otherLangs) {
        $targetJson = [System.IO.Path]::Combine($langDir, $lang + '.json')
        $result = Compare-Lang $baseJson $targetJson $lang
        $stats = $result.stats

        $missing = $stats.missingInTarget.Count
        $extra = $stats.extraInTarget.Count
        $translated = $stats.translatedTips
        $total = $stats.totalTips
        $rate = $result.rate

        if ($total -eq 0) { continue }

        $hasIssues = $missing -gt 0 -or $extra -gt 0 -or $rate -ne 100 -or $stats.typeMismatch.Count -gt 0 -or $stats.semanticMismatch.Count -gt 0 -or $stats.valueDiff.Count -gt 0 -or $stats.duplicateItems.Count -gt 0 -or $stats.meaninglessUsage.Count -gt 0 -or $stats.missingUsage.Count -gt 0 -or $stats.duplicateOptions.Count -gt 0 -or $stats.usageOrder.Count -gt 0 -or $stats.usageTooSimple.Count -gt 0 -or $stats.usageSeparator.Count -gt 0 -or $stats.optionMissingNext.Count -gt 0 -or $stats.forbiddenEmptyNext.Count -gt 0 -or $stats.usageRootPrefix.Count -gt 0

        $allResults += @{
            completion = $CompletionName
            lang       = $lang
            stats      = $stats
            rate       = $rate
            missing    = $missing
            extra      = $extra
            translated = $translated
            total      = $total
            hasIssues  = $hasIssues
        }
    }
}

if ($Json) {
    $jsonResults = @($allResults | ForEach-Object {
            $s = $_.stats
            @{
                completion = $_.completion
                lang       = $_.lang
                hasIssues  = $_.hasIssues
                rate       = $_.rate
                issues     = @{
                    missingInTarget    = @($s.missingInTarget | ForEach-Object { $_.path })
                    extraInTarget      = @($s.extraInTarget | ForEach-Object { $_.path })
                    typeMismatch       = @($s.typeMismatch | ForEach-Object { $_.path })
                    semanticMismatch   = @($s.semanticMismatch | ForEach-Object { "$($_.path)  —  $($_.reason)" })
                    valueDiff          = @($s.valueDiff | ForEach-Object { $_.path })
                    duplicateItems     = @($s.duplicateItems | ForEach-Object { $_.path })
                    untranslated       = @($s.untranslated | ForEach-Object { $_.path })
                    meaninglessUsage   = @($s.meaninglessUsage | ForEach-Object { $_.path })
                    missingUsage       = @($s.missingUsage | ForEach-Object { $_.path })
                    duplicateOptions   = @($s.duplicateOptions | ForEach-Object { $_.path })
                    usageOrder         = @($s.usageOrder | ForEach-Object { $_.path })
                    usageTooSimple     = @($s.usageTooSimple | ForEach-Object { $_.path })
                    usageSeparator     = @($s.usageSeparator | ForEach-Object { $_.path })
                    optionMissingNext  = @($s.optionMissingNext | ForEach-Object { $_.path })
                    forbiddenEmptyNext = @($s.forbiddenEmptyNext | ForEach-Object { $_.path })
                    usageRootPrefix    = @($s.usageRootPrefix | ForEach-Object { $_.path })
                }
            }
        })
    @{ results = $jsonResults } | ConvertTo-Json -Depth 10
    return
}

$issueResults = @()
$completeResults = @()
foreach ($r in $allResults) {
    if ($r.hasIssues) {
        $issueResults += $r
    }
    else {
        $completeResults += $r
    }
}
$totalFiles = $allResults.Count
$issueFiles = $issueResults.Count
$completedFiles = $completeResults.Count

outText $text.summary

if ($issueFiles -gt 0) {
    foreach ($r in $issueResults) {
        $targetShortPath = "$($r.completion)/$($r.lang).json"
        $missing = $r.missing
        $extra = $r.extra
        $translated = $r.translated
        $total = $r.total
        $rate = $r.rate
        $count = $r.stats.untranslated.Count
        outText $text.langHeader

        if ($r.stats.missingInTarget.Count -gt 0) {
            outText $text.missingInTarget
            foreach ($item in $r.stats.missingInTarget) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.extraInTarget.Count -gt 0) {
            outText $text.extraInTarget
            foreach ($item in $r.stats.extraInTarget) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.typeMismatch.Count -gt 0) {
            outText $text.typeMismatch
            foreach ($item in $r.stats.typeMismatch) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.semanticMismatch.Count -gt 0) {
            outText $text.semanticMismatch
            foreach ($item in $r.stats.semanticMismatch) {
                if ($item.reason) {
                    outText "<@Cyan>  $($item.path)<@Yellow>  —  $($item.reason)"
                }
                else {
                    outText "<@Cyan>  $($item.path)"
                }
            }
        }
        if ($r.stats.valueDiff.Count -gt 0) {
            outText $text.valueDiff
            foreach ($item in $r.stats.valueDiff) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.duplicateItems.Count -gt 0) {
            outText $text.duplicateItems
            foreach ($item in $r.stats.duplicateItems) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.untranslated.Count -gt 0) {
            outText $text.untranslated
            foreach ($item in $r.stats.untranslated) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.meaninglessUsage.Count -gt 0) {
            outText $text.meaninglessUsage
            foreach ($item in $r.stats.meaninglessUsage) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.missingUsage.Count -gt 0) {
            outText $text.missingUsage
            foreach ($item in $r.stats.missingUsage) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.duplicateOptions.Count -gt 0) {
            outText $text.duplicateOptions
            foreach ($item in $r.stats.duplicateOptions) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageOrder.Count -gt 0) {
            outText $text.usageOrder
            foreach ($item in $r.stats.usageOrder) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageTooSimple.Count -gt 0) {
            outText $text.usageTooSimple
            foreach ($item in $r.stats.usageTooSimple) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageSeparator.Count -gt 0) {
            outText $text.usageSeparator
            foreach ($item in $r.stats.usageSeparator) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.optionMissingNext.Count -gt 0) {
            outText $text.optionMissingNext
            foreach ($item in $r.stats.optionMissingNext) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.forbiddenEmptyNext.Count -gt 0) {
            outText $text.forbiddenEmptyNext
            foreach ($item in $r.stats.forbiddenEmptyNext) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageRootPrefix.Count -gt 0) {
            outText $text.usageRootPrefix
            foreach ($item in $r.stats.usageRootPrefix) { outText "<@Cyan>  $($item.path)" }
        }
    }
}

if ($completedFiles -gt 0) {
    Write-Host
    foreach ($r in $completeResults) {
        $targetShortPath = "$($r.completion)/$($r.lang).json"
        $translated = $r.translated
        $total = $r.total
        $rate = $r.rate
        outText $text.langHeaderComplete
    }
}
