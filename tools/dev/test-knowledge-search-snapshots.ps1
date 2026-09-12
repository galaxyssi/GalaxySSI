param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [string]$OutputDirectory = 'build/knowledge-search-snapshot-runs'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$classes = @('KnowledgeSearchSnapshotDeviceTest', 'AgentKnowledgeFtsDeviceTest',
    'KnowledgeHybridSearchDeviceTest', 'KnowledgeRetrievalAdmissionDeviceTest',
    'KnowledgePayloadCompactionDeviceTest', 'KnowledgePayloadUsageDeviceTest',
    'KnowledgePayloadDeviceTest', 'KnowledgeSourceSnapshotDeviceTest', 'KnowledgeBackupDeviceTest')
$selection = ($classes | ForEach-Object { "com.galaxyssi.chat.$_" }) -join ','
Write-Output "Running knowledge retrieval regressions on $Serial. Evidence: $directory"
$result = & $Adb -s $Serial shell am instrument -w -r -e class $selection `
    com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
$exitCode = $LASTEXITCODE
$lines = @($result | ForEach-Object { $_.ToString() })
$groups = @{}
$current = 'preamble'
foreach ($line in $lines) {
    if ($line -match '^INSTRUMENTATION_STATUS: class=com\.galaxyssi\.chat\.(\w+)$') { $current = $Matches[1] }
    if ($line -match '^INSTRUMENTATION_RESULT:') { $current = 'result' }
    if (!$groups.ContainsKey($current)) { $groups[$current] = [Collections.Generic.List[string]]::new() }
    $groups[$current].Add($line)
}
$utf8 = [Text.UTF8Encoding]::new($false)
$truncated = $false
foreach ($entry in $groups.GetEnumerator()) {
    $body = ($entry.Value -join "`n").TrimEnd() + "`n"
    if ($utf8.GetByteCount($body) -gt 30000 -or $entry.Value.Count -gt 1500) {
        $truncated = $true
        $body = (($entry.Value | Select-Object -First 1400) -join "`n")
        $body = $body.Substring(0, [Math]::Min(9500, $body.Length)).TrimEnd() + "`n[output truncated]`n"
    }
    [IO.File]::WriteAllText((Join-Path (Resolve-Path $directory) "$($entry.Key).txt"), $body, $utf8)
}
$passed = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: 0$' }).Count
$failures = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: -[12]$|FAILURES!!!' }).Count
if ($exitCode -ne 0 -or $passed -ne 66 -or $failures -ne 0 -or $truncated -or !($lines -contains 'OK (66 tests)')) {
    throw "Device regression failed: adb=$exitCode passed=$passed failures=$failures; see $directory"
}
$lines | Select-Object -Last 8 | Write-Output
Write-Output "Verified 66 device cases. Evidence: $directory"
