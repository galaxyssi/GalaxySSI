param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$ExpectedModel = 'SM-T575',
    [string]$CaseId = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()),
    [switch]$RebootDevice,
    [string]$Adb = (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)

$ErrorActionPreference = 'Stop'
if ($CaseId -notmatch '^[A-Za-z0-9-]{1,64}$') { throw 'Invalid case id' }
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$output = Join-Path $root "build/offline-effect-$CaseId"
if (Test-Path -LiteralPath $output) { throw 'Inspect the existing case instead of replacing its evidence' }
New-Item -ItemType Directory -Path $output | Out-Null

function Invoke-Adb([string[]]$Arguments, [switch]$AllowFailure) {
    $lines = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and !$AllowFailure) { throw "ADB failed: $($lines -join [Environment]::NewLine)" }
    return ($lines -join [Environment]::NewLine).Trim()
}

$model = Invoke-Adb @('shell', 'getprop', 'ro.product.model')
if (($model -replace '[_-]', '') -ne ($ExpectedModel -replace '[_-]', '')) {
    throw "Wrong device model: $model"
}
$packageInfo = Invoke-Adb @('shell', 'dumpsys', 'package', 'com.galaxyssi.chat')
$version = ($packageInfo -split '\r?\n' |
    Where-Object { $_ -match 'versionCode=|versionName=|firstInstallTime=|lastUpdateTime=' }) -join "`n"
$bootBefore = Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')
$prefix = "test-effect-observation-$CaseId"
$test = 'com.galaxyssi.chat.AgentNativeEffectObservationDeviceTest'
$runner = 'com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner'
$version | Set-Content -LiteralPath (Join-Path $output 'version.txt') -Encoding utf8

Write-Output "Preparing isolated crash case $CaseId on $model"
$prepare = Invoke-Adb -AllowFailure -Arguments @('shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
    "$test#crashAfterCompletedAndUncommittedRealWrites", '-e', 'effect_observation_prepare', 'true',
    '-e', 'effect_observation_case', $CaseId, $runner)
$prepare | Set-Content -LiteralPath (Join-Path $output 'prepare.log') -Encoding utf8
if ($prepare -notmatch 'Process crashed') { throw 'Expected deliberate process death was not observed; inspect prepare.log' }
$oldPid = Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$prefix.pid")
foreach ($suffix in @('completed', 'uncertain')) {
    $marker = Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$prefix.$suffix")
    if ($marker -ne 'one-write') { throw "Unexpected $suffix write marker before recovery" }
}

$bootAfter = $bootBefore
if ($RebootDevice) {
    Write-Output 'Rebooting the selected device; waiting for Android boot completion'
    $null = Invoke-Adb @('reboot')
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(4)
    $ready = $false
    do {
        Start-Sleep -Seconds 2
        try {
            $bootAfter = Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')
            $ready = $bootAfter -ne $bootBefore -and
                (Invoke-Adb @('shell', 'getprop', 'sys.boot_completed')) -eq '1'
        } catch { $ready = $false }
    } until ($ready -or [DateTimeOffset]::UtcNow -ge $deadline)
    if (!$ready) { throw 'Device boot did not complete; preserve the case and verify it after the device is available' }
}

Write-Output 'Recovering the two existing effects with tool availability disabled'
$verify = Invoke-Adb -AllowFailure -Arguments @('shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
    "$test#recoverBothWritesAfterProcessDeathWhileToolIsOffline", '-e', 'effect_observation_verify', 'true',
    '-e', 'effect_observation_case', $CaseId, $runner)
$verify | Set-Content -LiteralPath (Join-Path $output 'verify.log') -Encoding utf8
if ($verify -notmatch 'OK \(1 test\)' -or $verify -match 'FAILURES!!!|INSTRUMENTATION_STATUS_CODE: -[234]') {
    throw 'Recovery assertions did not pass; inspect verify.log without rerunning preparation'
}
$newPid = Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$prefix.verified")
if ($newPid -eq $oldPid) { throw 'Recovery must run in a new process' }
$report = [ordered]@{
    case_id = $CaseId; device = $model; serial = $Serial
    old_pid = $oldPid; new_pid = $newPid; physical_reboot = [bool]$RebootDevice
    boot_before = $bootBefore; boot_after = $bootAfter
    completed_effect_replayed = $true; interrupted_effect_not_reexecuted = $true
    production_data_cleared = $false; passed = $true
}
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'report.json') -Encoding utf8
$report | ConvertTo-Json
