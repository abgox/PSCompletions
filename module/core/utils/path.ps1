$PSCompletions | Add-Member -MemberType ScriptMethod fn_join_path {
    $res = $args[0]
    for ($i = 1; $i -lt $args.Count; $i++) {
        $res = Join-Path $res $args[$i]
    }
    return $res
}
