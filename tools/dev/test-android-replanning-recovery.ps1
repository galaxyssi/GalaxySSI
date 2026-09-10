param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$ExpectedModel = 'SM-T575',
    [string]$CaseId = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()),
    [ValidateSet('all', 'verify')][string]$Phase = 'all',
    [string]$Adb = (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
$ErrorActionPreference = 'Stop'
if ($CaseId -notmatch '^[A-Za-z0-9-]{1,64}$') { throw 'Invalid case id' }
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$output = Join-Path $root "build/replanning-$CaseId"
function Invoke-Adb([string[]]$Arguments, [switch]$AllowFailure) {
    $lines = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and !$AllowFailure) { throw "ADB failed: $($lines -join [Environment]::NewLine)" }
    return ($lines -join [Environment]::NewLine).Trim()
}
$model = Invoke-Adb @('shell', 'getprop', 'ro.product.model')
if (($model -replace '[_-]', '') -ne ($ExpectedModel -replace '[_-]', '')) { throw "Wrong device: $model" }
$name = "test-replanning-$CaseId"
$test = 'com.galaxyssi.chat.AgentReplanningDeviceTest'
$runner = 'com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner'
if ($Phase -eq 'all') {
    if (Test-Path -LiteralPath $output) { throw 'Preserve the existing case and use -Phase verify' }
    New-Item -ItemType Directory -Path $output | Out-Null
    $packageInfo = Invoke-Adb @('shell', 'dumpsys', 'package', 'com.galaxyssi.chat')
    ($packageInfo -split '\r?\n' | Where-Object { $_ -match 'versionCode=|versionName=|firstInstallTime=|lastUpdateTime=' }) |
        Set-Content -LiteralPath (Join-Path $output 'version.txt') -Encoding utf8
    $boot = Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')
    [ordered]@{ serial = $Serial; boot = $boot } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $output 'prepared.json') -Encoding utf8
    Write-Output "Preparing the interrupted replanning observation on $model"
    $prepare = Invoke-Adb -AllowFailure -Arguments @('shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
        "$test#interruptAfterTheReplanningToolObservationForPhysicalReboot", '-e', 'replanning_prepare', 'true',
        '-e', 'replanning_case', $CaseId, $runner)
    $prepare | Set-Content -LiteralPath (Join-Path $output 'prepare.log') -Encoding utf8
    if ($prepare -notmatch 'Process crashed') { throw 'Expected controlled process death was not observed' }
    $null = Invoke-Adb @('shell', 'am', 'force-stop', 'com.galaxyssi.chat')
    $null = Invoke-Adb @('reboot')
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(4)
    do {
        Start-Sleep -Seconds 2
        try {
            $ready = (Invoke-Adb @('shell', 'getprop', 'sys.boot_completed')) -eq '1' -and
                (Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')) -ne $boot
        } catch { $ready = $false }
    } until ($ready -or [DateTimeOffset]::UtcNow -ge $deadline)
    if (!$ready) { throw 'Boot did not complete; preserve this case and resume verification later' }
}
$prepared = Get-Content -LiteralPath (Join-Path $output 'prepared.json') -Raw | ConvertFrom-Json
if ($prepared.serial -ne $Serial) { throw 'Case belongs to another device' }
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$oldPid = Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$name.pid")
Write-Output 'Restoring the same runtime checkpoint; no task or completed tool is resubmitted'
$verify = Invoke-Adb -AllowFailure -Arguments @('shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
    "$test#restoreOriginalReplanningAfterPhysicalReboot", '-e', 'replanning_verify', 'true',
    '-e', 'replanning_case', $CaseId, $runner)
$verify | Set-Content -LiteralPath (Join-Path $output "verify-$stamp.log") -Encoding utf8
if ($verify -notmatch 'OK \(1 test\)' -or $verify -match 'FAILURES!!!|INSTRUMENTATION_STATUS_CODE: -[234]') {
    throw 'Replanning recovery failed; inspect the retained case and resume only verification'
}
$newPid = Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$name.verified")
$afterBoot = Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')
if ($newPid -eq $oldPid -or $afterBoot -eq $prepared.boot) { throw 'New process and physical reboot not verified' }
$report = [ordered]@{
    case_id = $CaseId; serial = $Serial; device = $model; old_pid = $oldPid; new_pid = $newPid
    boot_before = $prepared.boot; boot_after = $afterBoot; automatic_startup_worker = $false
    model_adapter = 'controlled'; native_observation = 'fsynced_file_append'; native_effect_count = 1
    task_resubmitted = $false; production_data_cleared = $false; passed = $true
}
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output "report-$stamp.json") -Encoding utf8
$report | ConvertTo-Json
