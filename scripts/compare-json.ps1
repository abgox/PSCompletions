#Requires -Version 7.0

param(
    [string]$CompletionName, # 完成项名称
    [string]$TargetLang = 'zh-CN',
    [string]$BaseLang = 'en-US',
    [ValidateSet('diff', 'untranslated')]
    [string[]]$Show = @('diff', 'untranslated')
)

Set-StrictMode -Off

$completion_name = $CompletionName

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    Write-Host $text.'import-psc' -ForegroundColor Red
    return
}

$text = $text.'compare-json'

function outText {
    param($text)
    $PSCompletions.write_with_color($PSCompletions.replace_content($text))
}

if (!$completion_name.Trim()) {
    outText $text.invalidName
    return
}
if ($TargetLang -eq $BaseLang) {
    outText $text.sameLang
    return
}

$completion_dir = [System.IO.Path]::Combine($PSScriptRoot, '..', 'completions', $completion_name)

$diffJson = [System.IO.Path]::Combine($completion_dir, 'language', $TargetLang + '.json')
if (!(Test-Path $diffJson)) {
    outText $text.invalidLang
    return
}

$baseJson = [System.IO.Path]::Combine($completion_dir, 'language', $BaseLang + '.json')

& $PSScriptRoot\sort-completion.ps1 $completion_name

function Compare-JsonProperty {
    param (
        [string]$diffJson,
        [string]$baseJson,
        [switch]$ReturnRate
    )

    # 读取 JSON 文件
    $diffContent = Get-Content -Path $diffJson -Raw | ConvertFrom-Json -AsHashtable
    $baseContent = Get-Content -Path $baseJson -Raw | ConvertFrom-Json -AsHashtable

    $is_psc = $diffJson -match '.*[\/\\]completions[\/\\]psc[\/\\]language[\/\\].*'

    # 统计
    $count = @{
        totalTips        = 0   # 总的 tip 数量

        diffList         = @() # 不同的属性值或类型
        untranslatedList = @() # 未翻译的
    }

    function noTranslated() {
        param($diffStr, $baseStr)
        # XXX: 以中文为例，可以通过判断是否存在中文字符
        # 直接判断是否相等，目前也可用

        # psc 有些特殊，不使用 replace_content
        if ($is_psc) {
            return $diffStr -ceq $baseStr
        }

        try {
            $json = $diffContent
            $info = $diffContent.info
            $diff = $PSCompletions.replace_content($diffStr)
        }
        catch {
            Write-Host "Error in $(Resolve-Path $diffJson)" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host $diffStr
            exit 1
        }

        try {
            $json = $baseContent
            $info = $baseContent.info
            $base = $PSCompletions.replace_content($baseStr)
        }
        catch {
            Write-Host "Error in $(Resolve-Path $baseJson)" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host $baseStr
            exit 1
        }
        return $diff -ceq $base
    }

    function isExist {
        param($v)
        # XXX: 在 PowerShell 中，对于空数组，以下两种判断都返回空，而非布尔。空又会被当做 false
        # @() -eq $null # 返回空，也就是 false
        # @() -ne $null # 返回空，也就是 false
        # 因此，如果它的类型是一个数组，就应该认为它存在
        return $v -is [array] -or $v -ne $null
    }

    # 定义递归函数以遍历
    function traverseArr {
        param (
            [array]$diffArr, # 比对
            [array]$baseArr, # 基准
            [string]$pos = ''
        )
        $baseIndex = 0
        $diffIndex = 0

        while ($baseIndex -lt $baseArr.Count -or $diffIndex -lt $diffArr.Count) {
            $baseItem = if ($baseIndex -lt $baseArr.Count) { $baseArr[$baseIndex] } else { $null }
            $diffItem = if ($diffIndex -lt $diffArr.Count) { $diffArr[$diffIndex] } else { $null }

            # name
            $isDiff = $false
            if ($baseItem.name) {
                if ($diffItem.name) {
                    if ($baseItem.name -cne $diffItem.name) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }

            }
            else {
                if ($diffItem.name) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    base = $baseItem.name
                    diff = $diffItem.name
                    pos  = "$pos[$baseIndex].name"
                }
                return
            }

            # alias
            $isDiff = $false
            if ($baseItem.alias) {
                if ($diffItem.alias) {
                    if (Compare-Object $baseItem.alias $diffItem.alias -CaseSensitive) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($diffItem.alias) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem.alias -join ' '
                    diff = $diffItem.alias -join ' '
                    pos  = "$pos[$baseIndex].alias"
                }
                return
            }

            # hide
            $isDiff = $false
            if ($null -ne $baseItem.hide) {
                if ($null -ne $diffItem.hide) {
                    if ($baseItem.hide -ne $diffItem.hide) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($null -ne $diffItem.hide) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem.hide
                    diff = $diffItem.hide
                    pos  = "$pos[$baseIndex].hide"
                }
                return
            }

            # next
            # options
            foreach ($item in @('next', 'options')) {
                $isDiff = $false
                if (isExist $baseItem.$item) {
                    if (isExist $diffItem.$item) {
                        $baseType = $baseItem.$item.GetType().Name
                        $diffType = $diffItem.$item.GetType().Name
                        if ($baseType -ne $diffType) {
                            $isDiff = $true
                        }
                    }
                    else {
                        $isDiff = $true
                    }
                }
                else {
                    if (isExist $diffItem.$item) {
                        $isDiff = $true
                    }
                }
                if ($isDiff) {
                    $count.diffList += @{
                        name = $baseItem.name
                        base = if ($baseItem.$item -is [array] -and $baseItem.$item.Count -eq 0) { '[]' }else { $baseItem.$item }
                        diff = if ($diffItem.$item -is [array] -and $diffItem.$item.Count -eq 0) { '[]' }else { $diffItem.$item }
                        pos  = "$pos[$baseIndex].$item"
                    }
                    return
                }

                if ($baseItem.$item -is [array] -and $diffItem.$item -is [array]) {
                    traverseArr $diffItem.$item $baseItem.$item "$pos[$baseIndex].$item"
                }
            }

            # value
            $isDiff = $false
            if ($null -ne $baseItem.value) {
                if ($null -ne $diffItem.value) {
                    if ($baseItem.value -cne $diffItem.value) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($null -ne $diffItem.value) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem.value
                    diff = $diffItem.value
                    pos  = "$pos[$baseIndex].value"
                }
                return
            }

            # values
            $isDiff = $false
            if (isExist $baseItem['values']) {
                if (isExist $diffItem['values']) {
                    if (Compare-Object $baseItem['values'] $diffItem['values'] -CaseSensitive) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if (isExist $diffItem['values']) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem['values'] -join ' '
                    diff = $diffItem['values'] -join ' '
                    pos  = "$pos[$baseIndex].values"
                }
                return
            }

            # tip
            $isDiff = $false
            if ($baseItem.tip) {
                $count.totalTips++
                if ($diffItem.tip) {
                    if (noTranslated $diffItem.tip $baseItem.tip) {
                        $count.untranslatedList += @{
                            name  = $diffItem.name
                            value = "`n" + ($diffItem.tip -join "`n")
                            pos   = "$pos[$baseIndex].tip"
                        }
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($diffItem.tip) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = "`n" + ($baseItem.tip -join "`n")
                    diff = "`n" + ($diffItem.tip -join "`n")
                    pos  = "$pos[$baseIndex].tip"
                }
                return
            }

            $baseIndex++
            $diffIndex++
        }
    }

    foreach ($item in @('root', 'options', 'common_options', 'config')) {
        if ($count.diffList.Count -gt 0) {
            break
        }
        $isDiff = $false
        if ($baseContent.$item.Count) {
            if ($diffContent.$item.Count) {
                traverseArr $diffContent.$item $baseContent.$item $item
            }
            else {
                $isDiff = $true
            }
        }
        else {
            if ($diffContent.$item.Count) {
                $isDiff = $true
            }
        }
        if ($isDiff) {
            $count.diffList += @{
                base = if ($baseContent.$item.Count) { '[ ... ]' }
                diff = if ($diffContent.$item.Count) { '[ ... ]' }
                pos  = $item
            }
            break
        }
    }

    if ($baseContent.info) {
        function traverseObj {
            param($diffObj, $baseObj, $pos)

            if ($null -eq $baseObj -or $null -eq $diffObj) {
                $count.diffList += @{
                    base = if ($null -ne $baseObj) { '{ ... }' }
                    diff = if ($null -ne $diffObj) { '{ ... }' }
                    pos  = $pos
                }
                return
            }

            $keys = @() + $diffObj.Keys + $baseObj.Keys | Sort-Object -Unique

            foreach ($key in $keys) {
                $isDiff = $false
                if (isExist $baseObj[$key]) {
                    if (isExist $diffObj[$key]) {
                        $baseType = $baseObj[$key].GetType().Name
                        $diffType = $diffObj[$key].GetType().Name
                        if ($baseType -ne $diffType) {
                            $isDiff = $true
                        }
                        else {
                            switch ($baseObj[$key]) {
                                { $_ -is [string] -or $_ -is [array] } {
                                    $diffStr = $diffObj[$key] -join ' '
                                    $baseStr = $baseObj[$key] -join ' '
                                    if ($diffStr -match '^https?://.+') {
                                        continue
                                    }
                                    if (noTranslated $diffStr $baseStr) {
                                        $count.totalTips++
                                        $count.untranslatedList += @{
                                            name  = $key
                                            value = $diffObj[$key]
                                            pos   = "$pos.$key"
                                        }
                                    }
                                }
                                { $_ -is [int] -or $_ -is [bool] } {
                                    if ($baseObj[$key] -cne $diffObj[$key]) {
                                        $isDiff = $true
                                    }
                                }
                                # 对象
                                default {
                                    traverseObj $diffObj[$key] $baseObj[$key] "$pos.$key"
                                }
                            }
                        }
                    }
                    else {
                        $isDiff = $true
                    }
                }
                else {
                    if (isExist $diffObj[$key]) {
                        $isDiff = $true
                    }
                }
                if ($isDiff) {
                    $count.diffList += @{
                        base = $baseObj[$key]
                        diff = $diffObj[$key]
                        pos  = "$pos.$key"
                    }
                    return
                }
            }
        }
        traverseObj $diffContent.info $baseContent.info 'info'
    }
    if ($count.diffList.Count -gt 0) {
        $completionRate = 0.01
    }
    else {
        if ($count.totalTips -gt 0) {
            $completionRate = 100 - ($count.untranslatedList.Count / $count.totalTips) * 100
        }
        else {
            $completionRate = 100
        }
    }
    $completionRate = [Math]::Max([Math]::Round($completionRate, 2), 0.01)

    if ($ReturnRate) {
        return $completionRate
    }

    $baseShortPath = Split-Path $baseJson -Leaf
    $diffShortPath = Split-Path $diffJson -Leaf

    outText $text.progress

    if ($count.diffList -and 'diff' -in $Show) {
        outText $text.diffList.tip
        foreach ($item in $count.diffList) {
            $prop = if ($null -eq $item.name) { '' }else { " (name: $($item.name))" }
            outText ($text.pos + $prop)
            outText $text.diffList.base
            outText $text.diffList.diff
        }
        outText $text.hr
    }

    if ($count.untranslatedList -and 'untranslated' -in $Show) {
        outText $text.untranslatedList.tip
        foreach ($item in $count.untranslatedList) {
            $prop = if ($null -eq $item.name) { '' }else { " (name: $($item.name))" }
            outText ($text.pos + $prop)
            outText $text.value
        }
        outText $text.hr
    }
}
Compare-JsonProperty $diffJson $baseJson
