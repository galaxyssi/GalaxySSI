param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [ValidateSet('focused', 'recovery')][string]$Phase = 'focused',
    [string]$OutputDirectory = 'build/knowledge-primary-copy-runs'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$fixture = 'test-primary-copy-' + [guid]::NewGuid().ToString('N') + '.db'
$deaths = @('before-frames', 'before-catalog', 'after-copy', 'before-verify-checkpoint', 'after-verify-checkpoint', 'before-publish', 'after-publish')
$steps = if ($Phase -eq 'focused') { @('focused') } else {
    @('prepare', 'before-frames', 'verify-before', 'before-catalog', 'verify-before', 'after-copy', 'prepare-verify',
        'before-verify-checkpoint', 'verify-copy', 'after-verify-checkpoint', 'before-publish', 'verify-not-published', 'after-publish', 'verify-published')
}
$index = 0
foreach ($step in $steps) {
    $options = @('-s', $Serial, 'shell', 'am', 'instrument', '-w', '-r')
    $expected = 1
    if ($Phase -eq 'focused') {
        $expected = 12
        $options += @('-e', 'class', 'com.galaxyssi.chat.KnowledgePrimaryCopyDeviceTest')
    } else {
        $options += @('-e', 'class', 'com.galaxyssi.chat.KnowledgePrimaryCopyRecoveryDeviceTest', '-e', 'copyFixture', $fixture, '-e', 'copyPhase', $step)
    }
    $options += 'com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner'
    Write-Output "Running primary copy $step. Evidence: $directory"
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
        $passed = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: 0$' }).Count
        if ($code -ne 0 -or $passed -ne $expected -or ($lines -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!') -or
            !($lines -match "^OK \($expected tests?\)$")) { throw "Primary copy test failed; see $directory" }
        $lines | Select-Object -Last 7 | Write-Output
    }
}
Write-Output "Verified primary copy $Phase. Evidence: $directory"
