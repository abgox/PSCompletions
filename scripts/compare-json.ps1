#Requires -Version 7.0

param(
    [string]$diffJson, # 比对文件，也可以简写补全名
    [string]$baseJson # 基准文件
)

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if ($PSEdition -ne 'Core') {
    Write-Host $text."need-pwsh" -ForegroundColor Red
    return
}

if (!$PSCompletions) {
    Write-Host $text."import-psc" -ForegroundColor Red
    return
}

$text = $text."compare-json"

function outText {
    param($text)
    $PSCompletions.write_with_color($PSCompletions.replace_content($text))
}

if ($diffJson -notmatch '\.json$') {
    $diffJson = Resolve-Path "$PSScriptRoot\..\completions\$diffJson\language\zh-CN.json"
}

if (!$diffJson -or !(Test-Path $diffJson)) {
    outText $text.invalidParams
    return
}

if (!$baseJson) {
    $completion_dir = Split-Path (Split-Path $diffJson -Parent) -Parent
    $path_config = Join-Path $completion_dir "config.json"
    $lang_list = (Get-Content -Path $path_config -Raw -Encoding utf8 | ConvertFrom-Json).language

    $baseJson = "$($completion_dir)/language/$($lang_list[0]).json"
}

function Compare-JsonProperty {
    param (
        [string]$diffJson,
        [string]$baseJson
    )

    # 读取 JSON 文件
    $diffContent = Get-Content -Path $diffJson -Raw | ConvertFrom-Json -AsHashtable
    $baseContent = Get-Content -Path $baseJson -Raw | ConvertFrom-Json -AsHashtable

    # 统计
    $count = @{
        totalTips        = 0   # 总的 tip 数量

        diffList         = @() # 不同的属性值或类型
        untranslatedList = @() # 未翻译的
        missingList      = @() # 缺少的
        extraList        = @() # 多余的
    }

    function noTranslated() {
        param($diffStr, $baseStr)
        # XXX: 以中文为例，可以通过判断是否存在中文字符
        # 直接判断是否相等，目前也可用
        return $diffStr -eq $baseStr
    }
    function _replace {
        param ($data, $separator = '')
        $data = $data -join $separator
        $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
        $matches = [regex]::Matches($data, $pattern)
        foreach ($match in $matches) {
            $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
        }
        if ($data -match $pattern) { (_replace $data) }else { return $data }
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
        for ($i = 0; $i -lt [Math]::Max($baseArr.Count, $diffArr.Count); $i++) {
            if (isExist $baseArr[$i]) {
                if (!(isExist $diffArr[$i])) {
                    $count.missingList += @{
                        pos = "$pos[$i]"
                    }
                }

                # name
                if (isExist $baseArr[$i].name) {
                    if (isExist $diffArr[$i].name) {
                        if ($baseArr[$i].name -ne $diffArr[$i].name) {
                            $count.diffList += @{
                                base = $baseArr[$i].name
                                diff = $diffArr[$i].name
                                pos  = "$pos[$i].name"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos   = "$pos[$i].name"
                            value = $baseArr[$i].name
                        }
                    }
                }
                else {
                    if (isExist $diffArr[$i].name) {
                        $count.extraList += @{
                            pos   = "$pos[$i].name"
                            value = $diffArr[$i].name
                        }
                    }
                }

                # alias
                if (isExist $baseArr[$i].alias) {
                    if (isExist $diffArr[$i].alias) {
                        if (Compare-Object $baseArr[$i].alias $diffArr[$i].alias -PassThru) {
                            $count.diffList += @{
                                base = $baseArr[$i].alias -join ' '
                                diff = $diffArr[$i].alias -join ' '
                                pos  = "$pos[$i].alias"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos   = "$pos[$i].alias"
                            value = $baseArr[$i].alias -join ' '
                        }
                    }
                }
                else {
                    if (isExist $diffArr[$i].alias) {
                        $count.extraList += @{
                            pos   = "$pos[$i].alias"
                            value = $diffArr[$i].alias -join ' '
                        }
                    }
                }

                # tip
                if (isExist $baseArr[$i].tip) {
                    $count.totalTips++
                    if (isExist $diffArr[$i].tip) {
                        $json = $diffContent
                        $info = $json.info
                        $diffStr = _replace $diffArr[$i].tip

                        $json = $baseContent
                        $info = $json.info
                        $baseStr = _replace $baseArr[$i].tip
                        if (noTranslated $diffStr $baseStr) {
                            $count.untranslatedList += @{
                                name  = $diffArr[$i].name
                                value = $diffArr[$i].tip
                                pos   = "$pos[$i].tip"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos   = "$pos[$i].tip"
                            value = $baseArr[$i].tip
                        }
                    }
                }
                else {
                    if (isExist $diffArr[$i].tip) {
                        $count.extraList += @{
                            pos   = "$pos[$i].tip"
                            value = $diffArr[$i].tip
                        }
                    }
                }
            }
            else {
                if (isExist $diffArr[$i]) {
                    $count.extraList += @{
                        pos = "$pos[$i]"
                    }
                }
            }

            # next
            # options
            foreach ($item in @('next', 'options')) {
                if (isExist $baseArr[$i].$item) {
                    if (isExist $diffArr[$i].$item) {
                        $baseType = $baseArr[$i].$item.GetType().Name
                        $diffType = $diffArr[$i].$item.GetType().Name
                        if ($baseType -ne $diffType) {
                            $count.diffList += @{
                                base = "$($baseArr[$i].$item)"
                                diff = "$($diffArr[$i].$item)"
                                pos  = "$pos[$i].$item"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos = "$pos[$i].$item"
                        }
                    }
                }
                else {
                    if (isExist $diffArr[$i].$item) {
                        $count.extraList += @{
                            pos = "$pos[$i].$item"
                        }
                    }
                }
                if ($baseArr[$i].$item -is [array] -and $diffArr[$i].$item -is [array]) {
                    traverseArr $diffArr[$i].$item $baseArr[$i].$item "$pos[$i].$item"
                }
            }
        }
    }

    foreach ($item in @('root', 'options', 'common_options')) {
        if ($baseContent.$item.Count) {
            if ($diffContent.$item.Count) {
                traverseArr $diffContent.$item $baseContent.$item $item
            }
            else {
                $count.missingList += @{
                    pos = $item
                }
            }
        }
        else {
            if ($diffContent.$item.Count) {
                $count.extraList += @{
                    pos = $item
                }
            }
        }
    }

    if ($baseContent.config.Count) {
        for ($i = 0; $i -lt [Math]::Max($baseContent.config.Count, $diffContent.config.Count); $i++) {
            if ($baseContent.config[$i]) {
                if (!(isExist $diffContent.config)) {
                    $count.missingList += @{
                        pos = "config"
                    }
                }

                if (!(isExist $diffContent.config[$i])) {
                    $count.missingList += @{
                        pos = "config[$i]"
                    }
                }

                # name
                # value
                foreach ($item in @('name', 'value')) {
                    if (isExist $baseContent.config[$i].$item) {
                        if (isExist $diffContent.config[$i].$item) {
                            $baseType = $baseContent.config[$i].$item.GetType().Name
                            $diffType = $diffContent.config[$i].$item.GetType().Name
                            if (($baseType -ne $diffType) -or ($baseContent.config[$i].$item -ne $diffContent.config[$i].$item)) {
                                $count.diffList += @{
                                    base = $baseContent.config[$i].$item
                                    diff = $diffContent.config[$i].$item
                                    pos  = "config[$i].$item"
                                }
                            }
                        }
                        else {
                            $count.missingList += @{
                                pos   = "config[$i].$item"
                                value = $baseContent.config[$i].$item
                            }
                        }
                    }
                    else {
                        if (isExist $diffContent.config[$i].$item) {
                            $count.extraList += @{
                                pos   = "config[$i].$item"
                                value = $diffContent.config[$i].$item
                            }
                        }
                    }
                }
                # values
                if (isExist $baseContent.config[$i].values) {
                    if (isExist $diffContent.config[$i].values) {
                        if (Compare-Object $baseContent.config[$i].values $diffContent.config[$i].values -PassThru) {
                            $count.diffList += @{
                                base = $baseContent.config[$i].values -join ' '
                                diff = $diffContent.config[$i].values -join ' '
                                pos  = "config[$i].values"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos   = "config[$i].values"
                            value = $baseContent.config[$i].values -join ' '
                        }
                    }
                }
                else {
                    if (isExist $diffContent.config[$i].values) {
                        $count.extraList += @{
                            pos   = "config[$i].values"
                            value = $diffContent.config[$i].values -join ' '
                        }
                    }
                }
                # tip
                if ($baseContent.config[$i].tip) {
                    $count.totalTips++

                    if (isExist $diffContent.config[$i].tip) {
                        $json = $diffContent
                        $info = $json.info
                        $diffStr = _replace $diffContent.config[$i].tip

                        $json = $baseContent
                        $info = $json.info
                        $baseStr = _replace $baseContent.config[$i].tip
                        if (noTranslated $diffStr $baseStr) {
                            $count.untranslatedList += @{
                                name  = $diffContent.config[$i].name
                                value = $diffContent.config[$i].tip
                                pos   = "$pos[$i].tip"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos   = "config[$i].tip"
                            value = $baseContent.config[$i].tip
                        }
                    }
                }
                else {
                    if ($diffContent.config[$i].tip) {
                        $count.extraList += @{
                            pos   = "config[$i].tip"
                            value = $diffContent.config[$i].tip
                        }
                    }
                }
            }
            else {
                if ($diffContent.config[$i]) {
                    $count.extraList += @{
                        pos = "config[$i]"
                    }
                }
            }
        }
    }

    if ($baseContent.info) {
        function traverseObj {
            param($diffObj, $baseObj, $pos)

            $keys = @() + $diffObj.Keys + $baseObj.Keys | Sort-Object -Unique

            foreach ($key in $keys) {
                if (isExist $baseObj[$key]) {
                    if (isExist $diffObj[$key]) {
                        $baseType = $baseObj[$key].GetType().Name
                        $diffType = $diffObj[$key].GetType().Name
                        if ($baseType -ne $diffType) {
                            $count.diffList += @{
                                base = $baseObj[$key]
                                diff = $diffObj[$key]
                                pos  = "$pos.$key"
                            }
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
                                    if ($baseObj[$key] -ne $diffObj[$key]) {
                                        $count.diffList += @{
                                            base = $baseObj[$key]
                                            diff = $diffObj[$key]
                                            pos  = "$pos.$key"
                                        }
                                    }
                                }
                                { $_ -is [array] } {
                                    if (Compare-Object $baseObj[$key] $diffObj[$key] -PassThru) {
                                        $count.diffList += @{
                                            base = $baseObj[$key] -join ' '
                                            diff = $diffObj[$key] -join ' '
                                            pos  = "$pos.$key"
                                        }
                                    }
                                }
                                # 对象
                                Default {
                                    traverseObj $diffObj[$key] $baseObj[$key] "$pos.$key"
                                }
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos = "$pos.$key"
                        }
                    }
                }
                else {
                    if (isExist $diffObj[$key]) {
                        $count.extraList += @{
                            pos = "$pos.$key"
                        }
                    }
                }
            }
        }
        traverseObj $diffContent.info $baseContent.info 'info'
    }

    if ($count.totalTips -gt 0) {
        $completionRate = 100 - (($count.diffList.Count + $count.untranslatedList.Count + $count.missingList.Count + $count.extraList.Count) / $count.totalTips) * 100
    }
    else {
        $completionRate = 100
    }
    $completionRate = [Math]::Max([Math]::Round($completionRate, 2), 0.01)

    $baseShortPath = Split-Path $baseJson -Leaf
    $diffShortPath = Split-Path $diffJson -Leaf

    outText $text.progress

    if ($count.diffList) {
        outText $text.diffList.tip
        foreach ($item in $count.diffList) {
            outText $text.pos
            outText $text.diffList.base
            outText $text.diffList.diff
        }
        outText $text.hr
    }

    if ($count.untranslatedList) {
        outText $text.untranslatedList.tip
        foreach ($item in $count.untranslatedList) {
            outText $text.pos
            outText $text.prop
            outText $text.value
        }
        outText $text.hr
    }
    if ($count.missingList.Count) {
        outText $text.missingList.tip
        foreach ($item in $count.missingList) {
            outText $text.missingList.pos
            if (isExist $item.value) {
                outText $text.value
            }
        }
        outText $text.hr
    }
    if ($count.extraList.Count) {
        outText $text.extraList.tip
        foreach ($item in $count.extraList) {
            outText $text.extraList.pos
            if (isExist $item.value) {
                outText $text.value
            }
        }
        outText $text.hr
    }
}
Compare-JsonProperty $diffJson $baseJson
