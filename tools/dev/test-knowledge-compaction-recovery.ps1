param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [string]$OutputDirectory = 'build/knowledge-compaction-recovery',
    [string]$Fixture = '',
    [string]$StartPhase = 'prepare'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected recovery device' }
if (!$Fixture) {
    if ($StartPhase -ne 'prepare') { throw 'Resuming requires an explicit fixture' }
    $Fixture = "test-knowledge-payload-$([guid]::NewGuid()).db"
}
if ($Fixture -notmatch '^test-knowledge-payload-[a-f0-9-]{36}\.db$') { throw 'Invalid recovery fixture' }
$directory = Join-Path $OutputDirectory ($Fixture.Replace('.db', '') + '-run-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$phases = @('prepare', 'before-commit', 'verify-rollback', 'after-commit', 'verify-commit', 'prepare-copy', 'during-copy', 'verify-copy')
$start = [Array]::IndexOf($phases, $StartPhase)
if ($start -lt 0) { throw 'Unknown start phase' }
foreach ($phase in $phases[$start..($phases.Length-1)]) {
    Write-Output "Running $phase on $Serial with isolated fixture $fixture"
    $result = & $Adb -s $Serial shell am instrument -w -r `
        -e class com.galaxyssi.chat.KnowledgePayloadCompactionRecoveryDeviceTest `
        -e compaction_fixture $fixture -e compaction_phase $phase `
        com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
    $exitCode = $LASTEXITCODE
    $text = $result | Out-String
    $bounded = ($text -split '\r?\n' | ForEach-Object {
        if ($_.Length -gt 1000) { $_.Substring(0, 1000) + ' [line truncated]' } else { $_ }
    } | Select-Object -First 200) -join "`n"
    if ($bounded.Length -gt 8000) { $bounded = $bounded.Substring(0, 8000) + "`n[output truncated]" }
    $bounded.TrimEnd() | Set-Content -Encoding utf8 -LiteralPath (Join-Path $directory "$phase.txt")
    if ($phase -in @('before-commit', 'after-commit', 'during-copy')) {
        if ($text -notmatch '(?i)Process crashed|Process is crashing|INSTRUMENTATION_FAILED') { throw "Expected process death missing in $phase" }
    } elseif ($exitCode -ne 0 -or $text -notmatch 'OK \(1 test\)' -or $text -match 'FAILURES!!!') {
        throw "Recovery verification failed in $phase; see $directory"
    }
    Write-Output $bounded.Trim()
}
Write-Output "Verified compaction rollback, committed relocation and durable copy recovery. Retained fixture: $fixture. Evidence: $directory"
