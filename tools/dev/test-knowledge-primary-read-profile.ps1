param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [ValidateSet('before','after')][string]$Phase = 'before'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path 'build/knowledge-primary-read-runs' ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$started = [long]((& $Adb -s $Serial shell date +%s | Out-String).Trim())
Write-Output "Running retained primary read profile $Phase. Evidence: $directory"
$result = & $Adb -s $Serial shell am instrument -w -r -e class com.galaxyssi.chat.KnowledgePrimaryReadProfileDeviceTest `
    -e retainedKnowledgeFixture 'test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db' `
    -e readProfilePhase $Phase com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
$code = $LASTEXITCODE
$lines = @($result | ForEach-Object { $_.ToString() })
$lines | Set-Content -LiteralPath (Join-Path $directory 'instrumentation.txt') -Encoding utf8
& $Adb -s $Serial logcat -d -v epoch -s System.out:I | Where-Object {
    $_ -match '^\s*(\d+)\.\d+.*KNOWLEDGE_PRIMARY_READ_PROFILE' -and [long]$Matches[1] -ge $started
} | Set-Content -LiteralPath (Join-Path $directory 'metrics.txt') -Encoding utf8
if ($code -ne 0 -or @($lines | Where-Object { $_ -eq 'INSTRUMENTATION_STATUS_CODE: 0' }).Count -ne 1 -or
    ($lines -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!') -or !($lines -match '^OK \(1 test\)$')) { throw "Read profile failed; see $directory" }
Get-Content -LiteralPath (Join-Path $directory 'metrics.txt')
$lines | Select-Object -Last 7 | Write-Output
