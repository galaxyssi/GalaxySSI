param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [ValidateSet('focused', 'migration', 'recovery', 'legacy', 'counters', 'profile')][string]$Phase = 'focused',
    [string]$OutputDirectory = 'build/knowledge-primary-runs'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$fixture = 'test-primary-recovery-' + [guid]::NewGuid().ToString('N') + '.db'
$steps = if ($Phase -eq 'recovery') {
    @('prepare', 'before-frames', 'verify-before', 'before-catalog', 'verify-before', 'after-catalog', 'verify-after')
} else { @($Phase) }
$index = 0
foreach ($step in $steps) {
    $options = @('-s', $Serial, 'shell', 'am', 'instrument', '-w', '-r')
    $expected = 1
    if ($Phase -eq 'focused') {
        $expected = 15
        $options += @('-e', 'class', 'com.galaxyssi.chat.KnowledgePrimaryPartitionsDeviceTest,com.galaxyssi.chat.KnowledgePrimaryStoreDeviceTest')
    } elseif ($Phase -in @('legacy', 'counters')) {
        if ($Phase -eq 'legacy') {
            $expected = 95
            $classes = @('AgentKnowledgeDatabaseDeviceTest', 'KnowledgeIdentityDeviceTest', 'KnowledgePayloadDeviceTest',
                'KnowledgePayloadCompactionDeviceTest', 'KnowledgePayloadUsageDeviceTest', 'KnowledgeRecordCryptoDeviceTest',
                'KnowledgeSourcePagingDeviceTest', 'KnowledgeSourceMigrationDeviceTest', 'KnowledgeSourcePreviewDeviceTest',
                'KnowledgeVectorLedgerDeviceTest', 'KnowledgeVectorChangesDeviceTest', 'KnowledgeVectorEnrollmentDeviceTest')
        } else {
            $expected = 22
            $classes = @('KnowledgeCountsDeviceTest', 'KnowledgeIndexedStatsDeviceTest', 'KnowledgeCountWorkerDeviceTest')
        }
        $selection = ($classes | ForEach-Object { "com.galaxyssi.chat.$_" }) -join ','
        $options += @('-e', 'class', $selection)
    } elseif ($Phase -eq 'profile') {
        $expected = 3
        $options += @('-e', 'class', 'com.galaxyssi.chat.KnowledgeCryptoProfileDeviceTest', '-e', 'retainedKnowledgeFixture',
            'test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db')
    } elseif ($Phase -eq 'migration') {
        $options += @('-e', 'class', 'com.galaxyssi.chat.KnowledgePrimaryRetainedDeviceTest', '-e', 'retainedKnowledgeFixture',
            'test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db')
    } else {
        $options += @('-e', 'class', 'com.galaxyssi.chat.KnowledgePrimaryRecoveryDeviceTest',
            '-e', 'primaryFixture', $fixture, '-e', 'primaryPhase', $step)
    }
    $options += 'com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner'
    Write-Output "Running primary partition $step. Evidence: $directory"
    $result = & $Adb @options 2>&1
    $code = $LASTEXITCODE
    $lines = @($result | ForEach-Object { $_.ToString() })
    $lines | Set-Content -LiteralPath (Join-Path $directory "$index-$step.txt") -Encoding utf8
    $index++
    if ($step -in @('before-frames', 'before-catalog', 'after-catalog')) {
        if (!($lines -match '(?i)Process crashed|Process is crashing|INSTRUMENTATION_FAILED')) { throw 'Expected process death missing' }
        $marker = (& $Adb -s $Serial shell run-as com.galaxyssi.chat cat "cache/$fixture.phase" | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $marker -ne $step) { throw 'Durable process death marker missing' }
        Write-Output "Verified intentional death at $step; retained fixture $fixture"
    } else {
        $passed = @($lines | Where-Object { $_ -match '^INSTRUMENTATION_STATUS_CODE: 0$' }).Count
        if ($code -ne 0 -or $passed -ne $expected -or ($lines -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!') -or
            !($lines -match "^OK \($expected tests?\)$")) { throw "Primary partition test failed; see $directory" }
        $lines | Select-Object -Last 7 | Write-Output
    }
}
Write-Output "Verified primary partition $Phase. Evidence: $directory"
