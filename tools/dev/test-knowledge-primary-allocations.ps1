param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [ValidateSet('focused','recovery')][string]$Phase = 'focused'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path 'build/knowledge-primary-allocation-runs' ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$fixture = 'test-primary-alloc-' + [guid]::NewGuid().ToString('N') + '.db'
$deaths = @('intent-only','before-catalog','after-unlink','after-catalog')
$steps = if ($Phase -eq 'focused') { @('focused') } else { @('intent-only','verify-empty','before-catalog','after-unlink','verify-empty','after-catalog','verify-committed') }
$index = 0
foreach ($step in $steps) {
    $options = @('-s',$Serial,'shell','am','instrument','-w','-r')
    $expected = 1
    if ($step -eq 'focused') { $expected = 14; $options += @('-e','class','com.galaxyssi.chat.KnowledgePrimaryAllocationDeviceTest') }
    else { $options += @('-e','class','com.galaxyssi.chat.KnowledgePrimaryAllocationRecoveryDeviceTest','-e','allocationFixture',$fixture,'-e','allocationPhase',$step) }
    $options += 'com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner'
    Write-Output "Running primary allocation $step. Evidence: $directory"
    $result = & $Adb @options 2>&1
    $code = $LASTEXITCODE
    $lines = @($result | ForEach-Object { $_.ToString() })
    $lines | Set-Content -LiteralPath (Join-Path $directory "$index-$step.txt") -Encoding utf8
    $index++
    if ($step -in $deaths) {
        if (!($lines -match '(?i)Process crashed|Process is crashing|INSTRUMENTATION_FAILED')) { throw 'Expected process death missing' }
        $marker = (& $Adb -s $Serial shell run-as com.galaxyssi.chat cat "cache/$fixture.phase" | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $marker -ne $step) { throw 'Durable death marker missing' }
        Write-Output "Verified death at $step; retained fixture $fixture"
    } else {
        if ($code -ne 0 -or @($lines | Where-Object { $_ -eq 'INSTRUMENTATION_STATUS_CODE: 0' }).Count -ne $expected -or
            ($lines -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!') -or !($lines -match "^OK \($expected tests?\)$")) { throw "Primary allocation test failed; see $directory" }
        $lines | Select-Object -Last 7 | Write-Output
    }
}
