#Requires -Version 7.0

Set-StrictMode -Off

$pattern = [regex]::new('\{\{(.*?(\})*)(?=\}\})\}\}', [System.Text.RegularExpressions.RegexOptions]::Compiled)
function replace_content {
    param ($data, $separator = '')
    $data = $data -join $separator
    if ($data -notlike '*{{*') { return $data }
    $matches = [regex]::Matches($data, $pattern)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
    }
    if ($data -match $pattern) { (replace_content $data) }else { return $data }
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
                        $diffStr = replace_content $diffArr[$i].tip

                        $json = $baseContent
                        $info = $json.info
                        $baseStr = replace_content $baseArr[$i].tip
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
                $baseValues = $baseContent.config[$i]['values']
                $diffValues = $diffContent.config[$i]['values']
                if (isExist $baseValues) {
                    if (isExist $diffValues) {
                        if (Compare-Object $baseValues $diffValues -PassThru) {
                            $count.diffList += @{
                                base = $baseValues -join ' '
                                diff = $diffValues -join ' '
                                pos  = "config[$i].values"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos   = "config[$i].values"
                            value = $baseValues -join ' '
                        }
                    }
                }
                else {
                    if (isExist $diffValues) {
                        $count.extraList += @{
                            pos   = "config[$i].values"
                            value = $diffValues -join ' '
                        }
                    }
                }
                # tip

                $baseTip = $baseContent.config[$i]['tip']
                $diffTip = $diffContent.config[$i]['tip']
                if ($baseTip) {
                    $count.totalTips++

                    if (isExist $diffTip) {
                        $json = $diffContent
                        $info = $json.info
                        $diffStr = replace_content $diffTip

                        $json = $baseContent
                        $info = $json.info
                        $baseStr = replace_content $baseTip
                        if (noTranslated $diffStr $baseStr) {
                            $count.untranslatedList += @{
                                name  = $diffContent.config[$i].name
                                value = $diffTip
                                pos   = "$pos[$i].tip"
                            }
                        }
                    }
                    else {
                        $count.missingList += @{
                            pos   = "config[$i].tip"
                            value = $baseTip
                        }
                    }
                }
                else {
                    if ($diffTip) {
                        $count.extraList += @{
                            pos   = "config[$i].tip"
                            value = $diffTip
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

    return $completionRate
}

function handle_language {
    param(
        [string]$name,
        [array]$lang_list = $lang_list
    )
    function getCompletionRate {
        param($lang)
        Compare-JsonProperty "$($_.FullName)/language/$($lang).json" "$($_.FullName)/language/$($lang_list[0]).json"
    }

    $lang_info = @("[**$($lang_list[0])**](/completions/$($name)/language/$($lang_list[0]).json)")
    if ($lang_list.Count -gt 1) {
        foreach ($lang in $lang_list[1..($lang_list.Count - 1)]) {
            $percentage = getCompletionRate $lang
            if ($lang -in $json_config.language) {
                $lang_info += "[**$($lang)($($percentage)%)**](/completions/$($name)/language/$($lang).json)"
            }
            else {
                $lang_info += "[**~~$($lang)($($percentage)%)~~**](/completions/$($name)/language/$($lang).json)"
            }
        }
    }
    return $lang_info
}

function generate_list {
    $content_EN = @("|Completion|Language|Description|", "|:-:|-|-|")
    $content_CN = @("|Completion|Language|Description|", "|:-:|-|-|")
    Get-ChildItem "$PSScriptRoot\..\completions" | ForEach-Object {
        $info_EN = @()
        $info_CN = @()
        $completion = @{}
        $json_config = Get-Content "$($_.FullName)/config.json" -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable

        $lang_list = Get-ChildItem "$($_.FullName)/language" | ForEach-Object { $_.BaseName }
        foreach ($lang in $lang_list) {
            $completion.$lang = Get-Content "$($_.FullName)/language/$($lang).json" -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        }
        if ("zh-CN" -notin $completion.Keys) {
            $completion."zh-CN" = $completion.($lang_list[0])
        }
        if ("en-US" -notin $completion.Keys) {
            $completion."en-US" = $completion.($lang_list[0])
        }
        if (!$completion."en-US".info) { $completion."en-US".info = $completion.($lang_list[0]).info }
        if (!$completion."zh-CN".info) { $completion."zh-CN".info = $completion.($lang_list[0]).info }

        # Completion
        ## EN
        $info_EN += "[$($_.Name)]($($completion."en-US".meta.url))"

        ## CN
        $info_CN += "[$($_.Name)]($($completion."zh-CN".meta.url))"

        # Language
        $lang_info = handle_language $_.BaseName $lang_list
        $info_EN += $lang_info -join '<br>'
        $info_CN += $lang_info -join '<br>'

        # Description
        ## EN
        $info_EN += ($completion."en-US".meta.description -join ' ') -replace '\n', '<br>'
        ## CN
        $info_CN += ($completion."zh-CN".meta.description -join ' ') -replace '\n', '<br>'

        $content_EN += "|" + ($info_EN -join "|") + "|"
        $content_CN += "|" + ($info_CN -join "|") + "|"
    }

    $footer = '|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|'

    $content_EN += $footer + "`n<!-- prettier-ignore-end -->"
    $content_CN += $footer + "`n<!-- prettier-ignore-end -->"

    return @{
        "en-US" = $content_EN
        "zh-CN" = $content_CN
    }
}

function handle($lang) {
    $content = generate_list
    if ($lang -eq "en-US") {
        $path = "$PSScriptRoot\..\completions.md"
        $content = $content."en-US"
    }
    else {
        $path = "$PSScriptRoot\..\completions.zh-CN.md"
        $content = $content."zh-CN"
    }
    function get_static_content($path) {
        $content = Get-Content -Path $path -Encoding UTF8

        $match = $content | Select-String -Pattern "<!-- prettier-ignore-start -->"

        if ($match) {
            $matchLineNumber = ([array]$match.LineNumber)[0]
            $result = $content | Select-Object -First $matchLineNumber
            $result
        }
    }
    (get_static_content $path) + $content | Out-File $path -Encoding UTF8 -Force
}

handle "en-US"
handle "zh-CN"
