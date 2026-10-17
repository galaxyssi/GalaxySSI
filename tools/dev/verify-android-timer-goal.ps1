param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$Adb = 'adb',
    [string]$ReportDirectory = (Join-Path $env:TEMP 'galaxyssi-timer-acceptance')
)

$ErrorActionPreference = 'Stop'
function Invoke-Adb([string[]]$Arguments) {
    $output = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    return ($output -join "`n")
}

# Instrumentation force-stops the target on Samsung and can disable accessibility.
# This debug-only audit uses the running App and never grants permissions itself.
$services = Invoke-Adb @('shell', 'dumpsys', 'accessibility')
if ($services -notmatch 'Bound services:\{Service\[[^\r\n]*com\.galaxyssi\.chat/\.GalaxySSIAccessibilityService') {
    throw 'GalaxySSI accessibility must already be enabled and bound on the selected device.'
}
$scope = 'timer-' + [guid]::NewGuid().ToString('N')
$rows = [Collections.Generic.List[object]]::new()
$cancelled = $false
$attempted = $false
$lastReceipt = ''
$failure = $null

function Invoke-Timer([string]$Operation, [Nullable[int]]$Seconds = $null) {
    $parameters = @{ timer_operation = $Operation }
    if ($null -ne $Seconds) { $parameters.timer_seconds = [int]$Seconds }
    $inputJson = @{ target = 'Android Timer'; parameters = $parameters } | ConvertTo-Json -Depth 5 -Compress
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($inputJson))
    $null = Invoke-Adb @('shell', 'am', 'broadcast', '-n', 'com.galaxyssi.chat/.AgentNativeToolAuditReceiver',
        '-a', 'com.galaxyssi.chat.DEBUG_NATIVE_TOOL_AUDIT', '--es', 'tool_id', 'galaxyssi.agent_action.set.alarm',
        '--es', 'input_base64', $payload, '--es', 'audit_scope', $scope)
    $result = (Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', 'files/native-tool-single.json')) | ConvertFrom-Json
    if ($result.tool_id -ne 'galaxyssi.agent_action.set.alarm' -or
        !$result.receipt.invocation_id -or $result.receipt.invocation_id -eq $script:lastReceipt) {
        throw 'The audit did not return a new timer receipt.'
    }
    $script:lastReceipt = $result.receipt.invocation_id
    $rows.Add([pscustomobject]@{ operation = $Operation; requested_seconds = $Seconds; result = $result })
    Write-Host "$Operation : $($result.status) / $($result.output.metadata.goal_status) / $($result.message)"
    return $result
}

function Assert-Verified($Result) {
    if ($Result.status -ne 'succeeded' -or $Result.output.metadata.goal_status -ne 'verified' -or
        $Result.output.metadata.business_success_verified -ne 'true') {
        throw "Goal not verified: $($Result.message)"
    }
}

try {
    $null = Invoke-Adb @('shell', 'am', 'start', '-n', 'com.galaxyssi.chat/.MainActivity')
    $attempted = $true
    $started = Invoke-Timer 'start' 60
    Assert-Verified $started
    $identity = $started.output.metadata.operation_id
    if (!$identity) { throw 'Missing operation identity.' }
    $repeated = Invoke-Timer 'start'
    Assert-Verified $repeated
    if ($repeated.output.metadata.operation_id -ne $identity) { throw 'Repeated start created another operation.' }
    $changed = Invoke-Timer 'replace' 120
    Assert-Verified $changed
    if (!$changed.output.metadata.operation_id -or $changed.output.metadata.operation_id -eq $identity) {
        throw 'Replacement did not establish a new verified timer.'
    }
    Assert-Verified (Invoke-Timer 'pause')
    Assert-Verified (Invoke-Timer 'resume')
    Assert-Verified (Invoke-Timer 'cancel')
    $cancelled = $true
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($attempted -and !$cancelled) {
        try {
            $cleanup = Invoke-Timer 'cancel'
            Assert-Verified $cleanup
            $cancelled = $true
        } catch { Write-Warning "Cleanup remains unverified; retain checkpoint $scope. $($_.Exception.Message)" }
    }
    $null = New-Item -ItemType Directory -Path $ReportDirectory -Force
    $path = Join-Path $ReportDirectory "$scope.json"
    [pscustomobject]@{ serial = $Serial; scope = $scope; passed = ($null -eq $failure); failure = $failure;
        cleanup_verified = $cancelled; completed_at = [DateTimeOffset]::Now.ToString('o'); steps = @($rows.ToArray()) } |
        ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
    Write-Host "Report: $path"
}
if ($failure) { throw $failure }
