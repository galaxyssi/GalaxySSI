param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [ValidateSet('focused', 'durable')][string]$Phase = 'focused',
    [string]$OutputDirectory = 'build/knowledge-statement-runs'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$started = [long]((& $Adb -s $Serial shell date +%s | Out-String).Trim())
$expected = if ($Phase -eq 'durable') { 1 } else { 12 }
$selection = if ($Phase -eq 'durable') { 'KnowledgeDurableLatencyDeviceTest' } else { 'KnowledgeStatementPoolDeviceTest' }
Write-Output "Running statement reuse $Phase acceptance. Evidence: $directory"
$result = & $Adb -s $Serial shell am instrument -w -r -e class "com.galaxyssi.chat.$selection" `
    -e retainedKnowledgeFixture 'test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db' `
    com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
$code = $LASTEXITCODE
$lines = @($result | ForEach-Object { $_.ToString() })
$lines | Set-Content -LiteralPath (Join-Path $directory 'instrumentation.txt') -Encoding utf8
& $Adb -s $Serial logcat -d -v epoch -s System.out:I | Where-Object {
    $_ -match '^\s*(\d+)\.\d+.*KNOWLEDGE_(STATEMENTS|DURABLE)_PROFILE' -and [long]$Matches[1] -ge $started
} | Set-Content -LiteralPath (Join-Path $directory 'metrics.txt') -Encoding utf8
$passed = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: 0$' }).Count
if ($code -ne 0 -or $passed -ne $expected -or ($lines -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!') -or
    !($lines -match "^OK \($expected tests?\)$")) { throw "Statement reuse acceptance failed; see $directory" }
$lines | Select-Object -Last 7 | Write-Output
Write-Output "Verified $expected statement reuse $Phase cases. Evidence: $directory"
