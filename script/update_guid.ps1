function info() {
    if ($PSCompletions.lang -eq 'zh-CN') {
        return @{
            select  = '选择一个或多个补全(按住Ctrl键选择多个)'
            confirm = '<$Yellow>是否更新以下补全的guid.txt?' + "`n" + '<$Cyan>按下 Enter 更新,其他任意键终止' + "`n" + '<$Magenta>{{$selected}}'
            updated = '<$Cyan>已更新 <$Magenta>{{$_}}<$Cyan> 的 guid.txt'
        }
    }
    else {
        return @{
            select  = 'Select one or more completion(Hold down the Ctrl key to select multiple)'
            confirm = '<$Yellow>Update The file(guid.txt) of the following completion?' + "`n" + '<$Cyan>Press Enter to update,Other keys to terminate' + "`n" + '<$Magenta>{{$selected}})'
            updated = '<$Cyan>The file(guid.txt) of <$Magenta>{{$_}} has been updated.'
        }
    }
}
$completions_items = (Get-ChildItem "$PSScriptRoot/../completions").BaseName

$info = info
$selected = $completions_items | Out-GridView -OutputMode Multiple -Title $info.select
if($selected){
    $null = $PSCompletions.fn_confirm(
        $info.confirm,
        {
            $selected | ForEach-Object {
                (New-Guid).Guid | Out-File "$PSScriptRoot/../completions/$_/guid.txt"
                $PSCompletions.fn_write($PSCompletions.fn_replace($info.updated))
            }
        }
    )
}
# function info() {
#     if ($PSCompletions.lang -eq 'zh-CN') {
#         return @{
#             confirm = '<$Yellow>请选择选项(<$Magenta>空格<$Yellow>选择/<$Magenta>回车<$Yellow>键确认):'
#             updated = '<$Cyan>已更新 <$Magenta>{{$_}}<$Cyan> 的 guid.txt'
#         }
#     }
#     else {
#         return @{
#             confirm = '<$Yellow>Please select item(<$Magenta>Space<$Yellow> to select/<$Magenta>Enter<$Yellow> key to confirm):'
#             updated = '<$Cyan>The file(guid.txt) of <$Magenta>{{$_}} has been updated.'
#         }
#     }
# }
# function Show-Items($items, $index) {
#     Clear-Host
#     $PSCompletions.fn_write($info.confirm)
#     for ($i = 0; $i -lt $items.Count; $i++) {
#         $is_selected = $items[$i] -in $selected_items
#         $checkbox = if ($is_selected) { '[x]' } else { '[ ]' }
#         if ($i -eq $index) {
#             Write-Host "$checkbox $($items[$i])" -ForegroundColor Green
#         }
#         else {
#             Write-Host "$checkbox $($items[$i])"
#         }
#     }
# }

# $info = info
# $completions_items = (Get-ChildItem "$PSScriptRoot/../completions").BaseName
# $selected_items = [System.Collections.Generic.List[string]]@()
# $selected_index = 0

# :loop while ($true) {
#     Show-Items $completions_items $selected_index
#     $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode

#     switch ($key) {
#         32 {
#             # Space
#             $current_item = $completions_items[$selected_index]
#             if ($current_item -in $selected_items) {
#                 $selected_items.Remove($current_item)
#             }
#             else {
#                 $selected_items.Add($current_item)
#             }
#         }
#         13 {
#             # Enter
#             break loop
#         }
#         38 {
#             # Up
#             $selected_index -= 1
#             if ($selected_index -lt 0) {
#                 $selected_index = $completions_items.Count - 1
#             }
#         }
#         40 {
#             # Down
#             $selected_index += 1
#             if ($selected_index -gt $completions_items.Count - 1) {
#                 $selected_index = 0
#             }
#         }
#     }

# }
# $selected_items | ForEach-Object {
#     (New-Guid).Guid | Out-File "$PSScriptRoot/../completions/$_/guid.txt"
#     $PSCompletions.fn_write($PSCompletions.fn_replace($info.updated))
# }
