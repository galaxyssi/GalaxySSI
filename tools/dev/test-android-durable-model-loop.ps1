param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$ExpectedModel = 'SM-T575',
    [string]$CaseId = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()),
    [ValidateSet('all', 'verify')][string]$Phase = 'all',
    [switch]$RebootDevice,
    [string]$Adb = (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)

$ErrorActionPreference = 'Stop'
if ($CaseId -notmatch '^[A-Za-z0-9-]{1,64}$') { throw 'Invalid case id' }
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$output = Join-Path $root "build/durable-model-loop-$CaseId"
function Invoke-Adb([string[]]$Arguments, [switch]$AllowFailure) {
    $lines = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and !$AllowFailure) { throw "ADB failed: $($lines -join [Environment]::NewLine)" }
    return ($lines -join [Environment]::NewLine).Trim()
}
$model = Invoke-Adb @('shell', 'getprop', 'ro.product.model')
if (($model -replace '[_-]', '') -ne ($ExpectedModel -replace '[_-]', '')) { throw "Wrong device: $model" }
$prefix = "test-model-loop-$CaseId"
$test = 'com.galaxyssi.chat.AgentDurableModelLoopDeviceTest'
$runner = 'com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner'

if ($Phase -eq 'all') {
    if (Test-Path -LiteralPath $output) { throw 'Existing case: inspect evidence and resume with -Phase verify' }
    New-Item -ItemType Directory -Path $output | Out-Null
    $packageInfo = Invoke-Adb @('shell', 'dumpsys', 'package', 'com.galaxyssi.chat')
    $version = ($packageInfo -split '\r?\n' |
        Where-Object { $_ -match 'versionCode=|versionName=|firstInstallTime=|lastUpdateTime=' }) -join "`n"
    $version | Set-Content -LiteralPath (Join-Path $output 'version.txt') -Encoding utf8
    [ordered]@{ serial = $Serial; boot = (Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')) } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'prepared.json') -Encoding utf8
    Write-Output "Preparing isolated model-loop process-death case $CaseId on $model"
    $prepare = Invoke-Adb -AllowFailure -Arguments @('shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
        "$test#stopAfterACommittedObservationBeforeTheNextModelReply", '-e', 'model_loop_prepare', 'true',
        '-e', 'model_loop_case', $CaseId, $runner)
    $prepare | Set-Content -LiteralPath (Join-Path $output 'prepare.log') -Encoding utf8
    if ($prepare -notmatch 'Process crashed') { throw 'Expected deliberate process death was not observed' }
}
$prepared = Get-Content -LiteralPath (Join-Path $output 'prepared.json') -Raw | ConvertFrom-Json
if ($prepared.serial -ne $Serial) { throw 'The case belongs to a different device' }
$oldPid = Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$prefix.pid")
foreach ($marker in @(@('effect', 'one-write'), @('model', 'one-request'))) {
    if ((Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$prefix.$($marker[0])")) -ne $marker[1]) {
        throw "Unexpected retained marker $($marker[0]); preserve the case"
    }
}
if ($RebootDevice) {
    Write-Output 'Rebooting the selected device before restoring the existing model loop'
    $beforeReboot = Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')
    $null = Invoke-Adb @('reboot')
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(4)
    do {
        Start-Sleep -Seconds 2
        try {
            $ready = (Invoke-Adb @('shell', 'getprop', 'sys.boot_completed')) -eq '1' -and
                (Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')) -ne $beforeReboot
        } catch { $ready = $false }
    } until ($ready -or [DateTimeOffset]::UtcNow -ge $deadline)
    if (!$ready) { throw 'Boot did not complete; resume the same case with -Phase verify' }
}
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Write-Output 'Restoring the observation and requesting only the missing second model response'
$verify = Invoke-Adb -AllowFailure -Arguments @('shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
    "$test#resumeTheModelWithItsExistingObservationAfterProcessDeath", '-e', 'model_loop_verify', 'true',
    '-e', 'model_loop_case', $CaseId, $runner)
$verify | Set-Content -LiteralPath (Join-Path $output "verify-$stamp.log") -Encoding utf8
if ($verify -notmatch 'OK \(1 test\)' -or $verify -match 'FAILURES!!!|INSTRUMENTATION_STATUS_CODE: -[234]') {
    throw 'Recovery assertions failed; preserve the original case and inspect the verification log'
}
$newPid = Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', "files/$prefix.verified")
if ($newPid -eq $oldPid) { throw 'Recovery must run in a different process' }
$boot = Invoke-Adb @('shell', 'cat', '/proc/sys/kernel/random/boot_id')
$report = [ordered]@{
    case_id = $CaseId; serial = $Serial; device = $model; old_pid = $oldPid; new_pid = $newPid
    boot_before = $prepared.boot; boot_after = $boot; physical_reboot = ($prepared.boot -ne $boot)
    model_round_resumed = 2; committed_tool_not_repeated = $true; completed_loop_replayed = $true
    provider = 'fixture'; production_data_cleared = $false; passed = $true
}
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output "report-$stamp.json") -Encoding utf8
$report | ConvertTo-Json
