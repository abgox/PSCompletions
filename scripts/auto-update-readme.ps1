function generate_list {
    $content_EN = @()
    $content_CN = @()
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
        if ($json_config.alias) {
            $info_EN += "[$($_.Name)($($json_config.alias))]($($completion."en-US".info.completion_info.url))"
        }
        else {
            $info_EN += "[$($_.Name)]($($completion."en-US".info.completion_info.url))"
        }
        ## CN
        if ($json_config.alias) {
            $info_CN += "[$($_.Name)($($json_config.alias))]($($completion."zh-CN".info.completion_info.url))"
        }
        else {
            $info_CN += "[$($_.Name)]($($completion."zh-CN".info.completion_info.url))"
        }

        # Language
        function handle_language($lang_list = $lang_list) {
            function Compare-JsonProperty {
                param (
                    [string]$DifferenceJsonPath,
                    [string]$ReferenceJsonPath
                )

                # 读取 JSON 文件
                $DifferenceContent = Get-Content -Path $DifferenceJsonPath -Raw | ConvertFrom-Json -AsHashtable
                $ReferenceContent = Get-Content -Path $ReferenceJsonPath -Raw | ConvertFrom-Json -AsHashtable

                # 初始化统计变量
                $count = @{
                    totalTips        = 0
                    untranslatedList = @() # 未翻译的
                    missingList      = @() # 缺少的
                    extraList        = @() # 多余的
                }

                function noTranslated() {
                    param($Difference, $Reference)
                    # XXX: 以中文为例，可以通过判断是否存在中文字符
                    # 直接判断是否相等，目前也可用
                    return $Difference -eq $Reference
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

                # 定义递归函数以遍历
                function Traverse {
                    param (
                        [array]$ReferenceArray,
                        [array]$DifferenceArray,
                        $attr = ''
                    )
                    for ($i = 0; $i -lt [Math]::Max($ReferenceArray.Count, $DifferenceArray.Count); $i++) {
                        if ($ReferenceArray[$i]) {
                            if ($ReferenceArray[$i].tip) {
                                $count.totalTips++
                                if ($DifferenceArray[$i].tip) {
                                    $json = $DifferenceContent
                                    $info = $json.info
                                    $Difference = _replace $DifferenceArray[$i].tip

                                    $json = $ReferenceContent
                                    $info = $json.info
                                    $Reference = _replace $ReferenceArray[$i].tip
                                    if (noTranslated $Difference $Reference) {
                                        $count.untranslatedList += @{
                                            value = $ReferenceArray[$i].tip
                                            attr  = "$($attr)[$($i)].tip"
                                        }
                                    }
                                }
                                else {
                                    $count.missingList += "$($attr)[$($i)].tip"
                                }
                            }
                            else {
                                if ($DifferenceArray[$i].tip) {
                                    $count.extraList += "$($attr)[$($i)].tip"
                                }
                            }
                        }
                        else {
                            if ($DifferenceArray[$i]) {
                                $count.extraList += "$($attr)[$($i)]"
                            }
                        }

                        # 处理 next 属性
                        if ($ReferenceArray[$i].next -and $DifferenceArray[$i].next) {
                            Traverse $ReferenceArray[$i].next $DifferenceArray[$i].next "$($attr)[$($i)].next"
                        }

                        # 处理 options 属性
                        if ($ReferenceArray[$i].options -and $DifferenceArray[$i].options) {
                            Traverse $ReferenceArray[$i].options $DifferenceArray[$i].options "$($attr)[$($i)].options"
                        }
                    }
                }

                if ($ReferenceContent.root) {
                    Traverse $ReferenceContent.root $DifferenceContent.root 'root'
                }
                if ($ReferenceContent.options) {
                    Traverse $ReferenceContent.options $DifferenceContent.options 'options'
                }
                if ($ReferenceContent.common_options) {
                    Traverse $ReferenceContent.common_options $DifferenceContent.common_options 'common_options'
                }

                if ($ReferenceContent.config) {
                    for ($i = 0; $i -lt [Math]::Max($ReferenceContent.config.Count, $DifferenceContent.config.Count); $i++) {
                        if ($ReferenceContent.config[$i].name -eq 'enable_hooks') {
                            continue
                        }
                        if ($ReferenceContent.config[$i]) {
                            if ($ReferenceContent.config[$i].tip) {
                                $count.totalTips++
                                if ($DifferenceContent.config[$i].tip) {
                                    $Difference = $DifferenceContent.config[$i].tip -join ''
                                    $Reference = $ReferenceContent.config[$i].tip -join ''
                                    if (noTranslated $Difference $Reference) {
                                        $count.untranslatedList += @{
                                            value = $DifferenceContent.config[$i].tip
                                            attr  = "config[$($i)].tip"
                                        }
                                    }
                                }
                                else {
                                    $count.missingList += "config[$($i)].tip"
                                }
                            }
                            else {
                                if ($DifferenceContent.config[$i].tip) {
                                    $count.extraList += "config[$($i)].tip"
                                }
                            }
                        }
                        else {
                            if ($DifferenceContent.config[$i]) {
                                $count.extraList += "config[$($i)]"
                            }
                        }
                    }
                }

                if ($ReferenceContent.info) {
                    if ($ReferenceContent.info.completion_info.description) {
                        $count.totalTips++
                        if ($DifferenceContent.info.completion_info.description) {
                            $Difference = $DifferenceContent.info.completion_info.description -join ''
                            $Reference = $ReferenceContent.info.completion_info.description -join ''
                            if (noTranslated $Difference $Reference) {
                                $count.untranslatedList += @{
                                    value = $ReferenceContent.info.completion_info.description
                                    attr  = "info.completion_info.description"
                                }
                            }
                        }
                        else {
                            $count.missingList += "info.completion_info.description"
                        }
                    }
                    else {
                        if ($DifferenceContent.info.completion_info.description) {
                            $count.extraList += "info.completion_info.description"
                        }
                    }
                }

                if ($count.totalTips -gt 0) {
                    $completionRate = 100 - (($count.untranslatedList.Count + $count.missingList.Count) / $count.totalTips) * 100
                }
                else {
                    $completionRate = 100
                }
                if ($count.extraList.Count) {
                    $completionRate += ($count.extraList.Count / $count.totalTips) * 100
                }
                if ($completionRate -gt 100) {
                    $completionRate = [Math]::Ceiling($completionRate)
                }
                else {
                    $completionRate = [Math]::Floor($completionRate)
                }

                return $completionRate
            }

            function getCompletionRate {
                param($lang)
                $DifferenceJsonPath = "$($_.FullName)/language/$($lang).json"
                $ReferenceJsonPath = "$($_.FullName)/language/$($lang_list[0]).json"
                Compare-JsonProperty $DifferenceJsonPath $ReferenceJsonPath
            }

            $lang_info = @("**$($lang_list[0])**")
            if ($lang_list.Count -gt 1) {
                foreach ($lang in $lang_list[1..($lang_list.Count - 1)]) {
                    $percentage = getCompletionRate $lang
                    if ($lang -in $json_config.language) {
                        $lang_info += "**$($lang)($($percentage)%)**"
                    }
                    else {
                        $lang_info += "**~~$($lang)($($percentage)%)~~**"
                    }
                }
            }
            return $lang_info
        }

        $lang_info = handle_language
        $info_EN += $lang_info -join '<br>'
        $info_CN += $lang_info -join '<br>'

        # Description
        ## EN
        $info_EN += ($completion."en-US".info.completion_info.description -join ' ') -replace '\n', '<br>'
        ## CN
        $info_CN += ($completion."zh-CN".info.completion_info.description -join ' ') -replace '\n', '<br>'

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
        $path = "$PSScriptRoot\..\README.md"
        $content = $content."en-US"
    }
    else {
        $path = "$PSScriptRoot\..\README-CN.md"
        $content = $content."zh-CN"
    }
    function get_static_content($path) {
        $content = Get-Content -Path $path -Encoding UTF8

        $match = $content | Select-String -Pattern "\|:-:\|-\|-\|"

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
