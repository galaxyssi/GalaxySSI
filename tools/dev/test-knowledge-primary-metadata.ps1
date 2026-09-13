param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path 'build/knowledge-primary-metadata-runs' ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
Write-Output "Running primary metadata acceptance. Evidence: $directory"
$result = & $Adb -s $Serial shell am instrument -w -r -e class com.galaxyssi.chat.KnowledgePrimaryMetadataDeviceTest `
    com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
$code = $LASTEXITCODE
$lines = @($result | ForEach-Object { $_.ToString() })
$lines | Set-Content -LiteralPath (Join-Path $directory 'focused.txt') -Encoding utf8
if ($code -ne 0 -or @($lines | Where-Object { $_ -eq 'INSTRUMENTATION_STATUS_CODE: 0' }).Count -ne 15 -or
    ($lines -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!') -or !($lines -match '^OK \(15 tests\)$')) {
    throw "Primary metadata acceptance failed; see $directory"
}
$lines | Select-Object -Last 7 | Write-Output
