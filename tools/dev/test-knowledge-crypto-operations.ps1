param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [string]$Fixture = 'test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db',
    [string]$OutputDirectory = 'build/knowledge-crypto-operations-runs'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
if ($Fixture -notmatch '^test-knowledge-source-replace-[a-f0-9-]+\.db$') { throw 'Only retained synthetic fixtures are allowed' }
$directory = Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$started = [long]((& $Adb -s $Serial shell date +%s | Out-String).Trim())
$classes = @('KnowledgeRecordCryptoDeviceTest', 'KnowledgeCryptoProfileDeviceTest', 'KnowledgeCryptoRetainedScaleDeviceTest')
$selection = ($classes | ForEach-Object { "com.galaxyssi.chat.$_" }) -join ','
Write-Output "Running authenticated crypto regressions. Evidence: $directory"
$result = & $Adb -s $Serial shell am instrument -w -r -e retainedKnowledgeFixture $Fixture -e class $selection `
    com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
$exitCode = $LASTEXITCODE
$lines = @($result | ForEach-Object { $_.ToString() })
$lines | Set-Content -LiteralPath (Join-Path $directory 'instrumentation.txt') -Encoding utf8
$metrics = & $Adb -s $Serial logcat -d -v epoch -s System.out:I
$metrics | Where-Object {
    $_ -match '^\s*(\d+)\.\d+.*KNOWLEDGE_CRYPTO_(PROFILE|SCALE|RETAINED_FIXTURE)' -and [long]$Matches[1] -ge $started
} | Set-Content -LiteralPath (Join-Path $directory 'metrics.txt') -Encoding utf8
$passed = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: 0$' }).Count
$failures = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!' }).Count
if ($exitCode -ne 0 -or $passed -ne 7 -or $failures -ne 0 -or !($lines -contains 'OK (7 tests)')) {
    throw "Crypto regression failed: adb=$exitCode passed=$passed failures=$failures; see $directory"
}
$lines | Select-Object -Last 8 | Write-Output
Write-Output "Verified seven device cases; the 10,001-body fixture is retained. Evidence: $directory"
