param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [string]$Fixture = 'test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db',
    [ValidateSet('regressions', 'rewrite')][string]$Phase = 'regressions',
    [ValidatePattern('^[a-z0-9-]{1,64}$')][string]$Variant = 'source-prepare-v1',
    [string]$OutputDirectory = 'build/knowledge-source-preparation-runs'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
if ($Fixture -notmatch '^test-knowledge-source-replace-[a-f0-9-]+\.db$') { throw 'Only retained synthetic fixtures are allowed' }
$directory = Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$started = [long]((& $Adb -s $Serial shell date +%s | Out-String).Trim())
$classes = @('KnowledgeSourceTimingDeviceTest', 'KnowledgeSourcePreparationDeviceTest', 'KnowledgeSourcePreparationScaleDeviceTest',
    'KnowledgeSourceReplaceDeviceTest', 'KnowledgeSourceStagingDeviceTest', 'KnowledgeBackupDeviceTest',
    'KnowledgeSourceRevisionDeviceTest', 'KnowledgeSourceDirectoryDeviceTest', 'KnowledgeSourceExportSnapshotDeviceTest',
    'KnowledgeSourceSnapshotDeviceTest', 'KnowledgeReadAdmissionDeviceTest', 'KnowledgeReadAdmissionScaleDeviceTest',
    'KnowledgeSearchSnapshotDeviceTest', 'KnowledgeHybridSearchDeviceTest', 'KnowledgeVectorReadAdmissionDeviceTest')
$expected = 97
if ($Phase -eq 'rewrite') { $classes = @('KnowledgeCryptoRetainedScaleDeviceTest'); $expected = 1 }
$selection = ($classes | ForEach-Object { "com.galaxyssi.chat.$_" }) -join ','
Write-Output "Running source preparation $Phase. Evidence: $directory"
$result = & $Adb -s $Serial shell am instrument -w -r -e retainedKnowledgeFixture $Fixture `
    -e retainedKnowledgeVariant $Variant -e class $selection `
    com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
$exitCode = $LASTEXITCODE
$lines = @($result | ForEach-Object { $_.ToString() })
$lines | Set-Content -LiteralPath (Join-Path $directory 'instrumentation.txt') -Encoding utf8
$metrics = & $Adb -s $Serial logcat -d -v epoch -s System.out:I
$metrics | Where-Object {
    $_ -match '^\s*(\d+)\.\d+.*KNOWLEDGE_(SOURCE_PREPARE|READ_ADMISSION|VECTOR_READ|CRYPTO_SCALE)' -and [long]$Matches[1] -ge $started
} | Set-Content -LiteralPath (Join-Path $directory 'metrics.txt') -Encoding utf8
$passed = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: 0$' }).Count
$failures = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!' }).Count
if ($exitCode -ne 0 -or $passed -ne $expected -or $failures -ne 0 -or !($lines -match "^OK \($expected tests?\)$")) {
    throw "Source preparation regression failed: adb=$exitCode passed=$passed failures=$failures; see $directory"
}
$lines | Select-Object -Last 8 | Write-Output
Write-Output "Verified $passed device cases for $Phase. Evidence: $directory"
