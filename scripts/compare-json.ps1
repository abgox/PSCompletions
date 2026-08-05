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
        totalTips        = 0
        translatedTips   = 0
        missingInTarget  = @()
        extraInTarget    = @()
        typeMismatch     = @()
        semanticMismatch = @()
        valueDiff        = @()
        untranslated     = @()
        duplicateItems   = @()
        tipOnlyUsage     = @()
        meaninglessUsage = @()
        missingUsage     = @()
        duplicateOptions = @()
        usageOrder       = @()
        usageTooSimple   = @()
        usageSeparator   = @()
    }

    function Normalize-Value {
        param($Value, [string]$Key = '')

        if ($null -eq $Value) { return $null }
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
        param($BaseVal, $TargetVal, [string]$Path)

        $baseArr = if ($null -eq $BaseVal) { @() } else { @($BaseVal) }
        $targetArr = if ($null -eq $TargetVal) { @() } else { @($TargetVal) }

        foreach ($item in $baseArr) {
            if ($item -isnot [string]) { return }
        }
        foreach ($item in $targetArr) {
            if ($item -isnot [string]) { return }
        }

        if ($baseArr.Count -eq 0 -and $targetArr.Count -eq 0) { return }
        if ($baseArr.Count -eq 0) { return }

        $stats.totalTips++

        if ($targetArr.Count -eq 0) {
            $stats.missingInTarget += @{ path = $Path; name = $Path }
            return
        }

        $baseStr = $baseArr -join ''
        $targetStr = $targetArr -join ''

        $isTemplate = $targetStr -like '{{*}}' -and $baseStr -like '{{*}}' -and $targetStr -eq $baseStr
        if ($isTemplate -or $targetStr -ne $baseStr) {
            $stats.translatedTips++
        }
        else {
            $stats.untranslated += @{ path = $Path; name = $Path }
        }
    }

    function Compare-Value {
        param($BaseVal, $TargetVal, [string]$Path, [string]$Key, [bool]$SkipValueCheck)

        if ($Key -in 'tip', 'description') {
            Compare-TranslatableText -BaseVal $BaseVal -TargetVal $TargetVal -Path $Path
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
                    $suffix = " (<@Red>$BaseVal<@Cyan> > <@Red>$TargetVal<@Cyan>)"
                    $stats.semanticMismatch += @{ path = "$Path$suffix"; name = $Path }
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

        $baseKeys = if ($BaseObj) { @($BaseObj.Keys) } else { @() }
        $targetKeys = if ($TargetObj) { @($TargetObj.Keys) } else { @() }
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

    function Validate-Tip {
        param([array]$Tip, [string]$Path)

        if ($null -eq $Tip -or $Tip.Count -eq 0) { return }

        $hasUsage = $false
        $hasDescription = $false

        foreach ($line in $Tip) {
            if ($line -match '^U:') {
                $hasUsage = $true
            }
            elseif ($line -match '^E:') {
                # Example line is OK
            }
            else {
                $hasDescription = $true
            }
        }

        if ($hasUsage -and -not $hasDescription) {
            $stats.tipOnlyUsage += @{ path = $Path; name = $Path }
        }
    }

    function Validate-UsageFormat {
        param([string]$Line, [string]$Path, [bool]$IsOption)

        $u = $Line.Substring(2).Trim()
        # 提取前导形式块：连续的由逗号/竖线分隔的形式，遇到空格、'<'、'='、'[' 等占位/列举处停止
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

        # usage 不是强制项：只有有别名时必须存在（用于展示别名）；有 next 或两者皆无时均可按需添加
        $needsUsage = $hasAlias

        $hasUsage = $false
        $useless = $false
        # 是否为选项：位于 option/global_option 数组，或名称以 '-' 开头（兼容把选项放在 next 数组里的写法）
        $isOptionLike = $IsOption -or ($Item.name -match '^-')
        if ($null -ne $Item.tip) {
            foreach ($line in @($Item.tip)) {
                if ($line -is [string] -and $line -match '^U:') {
                    Validate-UsageFormat -Line $line -Path $Path -IsOption $isOptionLike
                    if (-not $hasUsage) {
                        $hasUsage = $true
                        if ($line -match '^U:\s*(.*)$' -and $Matches[1].Trim() -eq $Item.name) {
                            $useless = $true
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

        # 根级 global_option：name、tip、next、option 等所有子结构都完全一致时，才视为与各层级 option 重复
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
        param([hashtable]$Content, [string]$BasePath, [bool]$IsOption = $false)

        if ($Content.tip) {
            Validate-Tip -Tip $Content.tip -Path $BasePath
        }
        if ($Content.name) {
            Validate-ItemUsage -Item $Content -Path $BasePath -IsOption $IsOption
        }

        if ($Content.next) {
            foreach ($sub in @($Content.next)) {
                if ($sub -is [hashtable] -and $sub.name) {
                    $subPath = if ($BasePath) { "$BasePath > $($sub.name)" } else { $sub.name }
                    Validate-AllTips -Content $sub -BasePath $subPath
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

        $hasIssues = $missing -gt 0 -or $extra -gt 0 -or $rate -ne 100 -or $stats.typeMismatch.Count -gt 0 -or $stats.semanticMismatch.Count -gt 0 -or $stats.valueDiff.Count -gt 0 -or $stats.duplicateItems.Count -gt 0 -or $stats.tipOnlyUsage.Count -gt 0 -or $stats.meaninglessUsage.Count -gt 0 -or $stats.missingUsage.Count -gt 0 -or $stats.duplicateOptions.Count -gt 0 -or $stats.usageOrder.Count -gt 0 -or $stats.usageTooSimple.Count -gt 0 -or $stats.usageSeparator.Count -gt 0

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
                    missingInTarget  = @($s.missingInTarget | ForEach-Object { $_.path })
                    extraInTarget    = @($s.extraInTarget | ForEach-Object { $_.path })
                    typeMismatch     = @($s.typeMismatch | ForEach-Object { $_.path })
                    semanticMismatch = @($s.semanticMismatch | ForEach-Object { $_.path })
                    valueDiff        = @($s.valueDiff | ForEach-Object { $_.path })
                    duplicateItems   = @($s.duplicateItems | ForEach-Object { $_.path })
                    untranslated     = @($s.untranslated | ForEach-Object { $_.path })
                    tipOnlyUsage     = @($s.tipOnlyUsage | ForEach-Object { $_.path })
                    meaninglessUsage = @($s.meaninglessUsage | ForEach-Object { $_.path })
                    missingUsage     = @($s.missingUsage | ForEach-Object { $_.path })
                    duplicateOptions = @($s.duplicateOptions | ForEach-Object { $_.path })
                    usageOrder       = @($s.usageOrder | ForEach-Object { $_.path })
                    usageTooSimple   = @($s.usageTooSimple | ForEach-Object { $_.path })
                    usageSeparator   = @($s.usageSeparator | ForEach-Object { $_.path })
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
            foreach ($item in $r.stats.semanticMismatch) { outText "<@Cyan>  $($item.path)" }
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
        if ($r.stats.tipOnlyUsage.Count -gt 0) {
            outText $text.tipOnlyUsage
            foreach ($item in $r.stats.tipOnlyUsage) { outText "<@Cyan>  $($item.path)" }
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
