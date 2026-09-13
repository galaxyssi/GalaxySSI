param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$directory = Join-Path 'build/knowledge-primary-reboot-runs' ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$fixture = 'test-primary-reboot-' + [guid]::NewGuid().ToString('N') + '.db'
$bootBefore = (& $Adb -s $Serial shell cat /proc/sys/kernel/random/boot_id | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $bootBefore -notmatch '^[a-f0-9-]{36}$') { throw 'Missing initial boot identity' }
function Invoke-RebootPhase([string]$Phase) {
    Write-Output "Running primary reboot $Phase. Evidence: $directory"
    $output = & $Adb -s $Serial shell am instrument -w -r -e class com.galaxyssi.chat.KnowledgePrimaryRebootDeviceTest `
        -e rebootFixture $fixture -e rebootPhase $Phase com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner 2>&1
    $code = $LASTEXITCODE
    $lines = @($output | ForEach-Object { $_.ToString() })
    $lines | Set-Content -Encoding utf8 -LiteralPath (Join-Path $directory "$Phase.txt")
    if ($code -ne 0 -or @($lines | Where-Object { $_ -eq 'INSTRUMENTATION_STATUS_CODE: 0' }).Count -ne 1 -or
        ($lines -match '^INSTRUMENTATION_STATUS_CODE: -[123]$|FAILURES!!!') -or !($lines -match '^OK \(1 test\)$')) { throw "Reboot $Phase failed; see $directory" }
    $lines | Select-Object -Last 7 | Write-Output
}
Invoke-RebootPhase 'prepare'
Write-Output 'Rebooting only SM-T575; unlock it if credential storage requires authentication.'
& $Adb -s $Serial reboot
if ($LASTEXITCODE -ne 0) { throw 'Device reboot request failed' }
$started = [DateTime]::UtcNow
$ready = $false
$bootAfter = ''
do {
    Start-Sleep -Seconds 2
    $state = (& $Adb -s $Serial get-state 2>&1 | Out-String).Trim()
    if ($state -ne 'device') { continue }
    $bootAfter = (& $Adb -s $Serial shell cat /proc/sys/kernel/random/boot_id 2>&1 | Out-String).Trim()
    if ($bootAfter -notmatch '^[a-f0-9-]{36}$' -or $bootAfter -eq $bootBefore) { continue }
    $completed = (& $Adb -s $Serial shell getprop sys.boot_completed 2>&1 | Out-String).Trim()
    if ($completed -ne '1') { continue }
    $null = & $Adb -s $Serial shell run-as com.galaxyssi.chat ls "databases/$fixture" 2>&1
    $ready = $LASTEXITCODE -eq 0
} while (!$ready -and ([DateTime]::UtcNow - $started).TotalSeconds -lt 180)
$boot = [ordered]@{fixture=$fixture;device=$Serial;model=$model;before=$bootBefore;after=$bootAfter;credentialStorageReady=$ready;waitSeconds=([DateTime]::UtcNow - $started).TotalSeconds}
$boot | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path $directory 'boot.json')
if (!$ready) { throw "Device not ready or locked. Retained fixture $fixture; see $directory" }
Invoke-RebootPhase 'verify'
& $Adb -s $Serial logcat -d -v epoch -s System.out:I | Where-Object { $_ -match 'KNOWLEDGE_PRIMARY_REBOOT ' } |
    Set-Content -Encoding utf8 -LiteralPath (Join-Path $directory 'metrics.txt')
Get-Content -LiteralPath (Join-Path $directory 'metrics.txt')
