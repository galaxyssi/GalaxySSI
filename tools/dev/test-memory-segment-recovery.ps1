param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = 'R52R90282TY',
    [string]$OutputDirectory = 'build/memory-segment-recovery'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $model -ne 'SM-T575') { throw "This recovery test requires SM-T575; found $model" }
$fixture = 'segments-recovery-' + [guid]::NewGuid().ToString('N')
$directory = Join-Path $OutputDirectory $fixture
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$phases = @('prepare', 'before-commit', 'verify-rollback', 'after-commit', 'verify-commit', 'cleanup',
    'copy-prepare', 'during-copy', 'verify-copy', 'copy-cleanup')
foreach ($phase in $phases) {
    Write-Output "Running $phase on $Serial with isolated fixture $fixture"
    $result = & $Adb -s $Serial shell am instrument -w -r -e class com.galaxyssi.chat.AgentMemorySegmentRecoveryDeviceTest `
        -e segment_fixture $fixture -e segment_phase $phase com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
    $exitCode = $LASTEXITCODE
    $text = $result | Out-String
    $text | Set-Content -Encoding utf8 -LiteralPath (Join-Path $directory "$phase.log")
    if ($phase -in @('before-commit', 'after-commit', 'during-copy')) {
        if ($text -notmatch '(?i)Process crashed|Process is crashing|INSTRUMENTATION_FAILED') {
            throw "Expected intentional process death was not observed in $phase. See $directory"
        }
    } elseif ($exitCode -ne 0 -or $text -notmatch 'OK \(1 test\)' -or $text -match 'FAILURES!!!') {
        throw "Recovery verification failed in $phase. See $directory"
    }
    Write-Output $text.Trim()
}
Write-Output "Verified three real process deaths and recovery. Raw evidence: $directory"
