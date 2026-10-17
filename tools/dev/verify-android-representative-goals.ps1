param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$Adb = 'adb',
    [string]$ReportDirectory = (Join-Path $env:TEMP 'galaxyssi-representative-acceptance')
)
$ErrorActionPreference = 'Stop'
$scope = 'representative-' + [guid]::NewGuid().ToString('N')
$rows = [Collections.Generic.List[object]]::new()
$checks = [Collections.Generic.List[string]]::new()
$failure = $null
$cleanup = $false
function Invoke-Adb([string[]]$Arguments) {
    $output = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    return ($output -join "`n")
}
function Invoke-Tool([string]$Name, [hashtable]$InputData, [switch]$ExpectFailure) {
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($InputData | ConvertTo-Json -Depth 10 -Compress)))
    $null = Invoke-Adb @('shell', 'am', 'broadcast', '-n', 'com.galaxyssi.chat/.AgentNativeToolAuditReceiver',
        '-a', 'com.galaxyssi.chat.DEBUG_NATIVE_TOOL_AUDIT', '--es', 'tool_id', $Name,
        '--es', 'input_base64', $payload, '--es', 'audit_scope', $scope)
    $result = (Invoke-Adb @('shell', 'run-as', 'com.galaxyssi.chat', 'cat', 'files/native-tool-single.json')) | ConvertFrom-Json
    if ($result.tool_id -ne $Name -or !$result.receipt.invocation_id -or
        $rows.result.receipt.invocation_id -contains $result.receipt.invocation_id) { throw 'Stale audit receipt.' }
    $rows.Add([pscustomobject]@{ tool = $Name; expected_failure = [bool]$ExpectFailure; result = $result })
    if ($ExpectFailure) {
        if ($result.status -eq 'succeeded' -or !$result.error.code) { throw "Expected structured failure from $Name" }
    } elseif ($result.status -ne 'succeeded') { throw "$Name : $($result.error.code) / $($result.message)" }
    return $result
}
function Read-Text([string]$Path) {
    return (Invoke-Tool 'galaxyssi.workspace.file.read.text' @{workspace_id=$scope; path=$Path}).output.text
}
function Write-Text([string]$Path, [string]$Text) {
    $null = Invoke-Tool 'galaxyssi.workspace.file.write.text' @{workspace_id=$scope; path=$Path; text=$Text; create_parents=$true}
}
function Check([string]$Name, [bool]$Condition) {
    if (!$Condition) { throw "Check failed: $Name" }
    $checks.Add($Name)
    Write-Host "PASS $Name"
}
try {
    $null = Invoke-Tool 'galaxyssi.workspace.initialize' @{workspace_id=$scope}
    $unicode = "# Synthetic report`n" + [char]0x4E2D + [char]0x6587 + " / English`n- evidence: local fixture`n"
    Write-Text 'fixtures/report.md' $unicode
    Check 'Unicode document save and exact readback' ((Read-Text 'fixtures/report.md') -ceq $unicode)

    $csv = "item,quantity,price,total`nnotebook,2,12,24`npen,3,5,15`n"
    Write-Text 'fixtures/budget.csv' $csv
    $data = (Read-Text 'fixtures/budget.csv') | ConvertFrom-Csv
    Check 'CSV rows and independent arithmetic verification' (($data.Count -eq 2) -and
        (($data | ForEach-Object { [int]$_.quantity * [int]$_.price } | Measure-Object -Sum).Sum -eq 39))

    $null = Invoke-Tool 'galaxyssi.workspace.file.patch.exact' @{workspace_id=$scope; path='fixtures/report.md';
        expected_text='absent stale revision'; replacement_text='must not appear'} -ExpectFailure
    Check 'Stale edit rejected without changing the document' ((Read-Text 'fixtures/report.md') -ceq $unicode)
    $null = Invoke-Tool 'galaxyssi.workspace.file.patch.exact' @{workspace_id=$scope; path='fixtures/report.md';
        expected_text='local fixture'; replacement_text='verified fixture'}
    Check 'Corrected follow-up edit preserves the rest' ((Read-Text 'fixtures/report.md') -ceq $unicode.Replace('local fixture','verified fixture'))

    $null = Invoke-Tool 'galaxyssi.workspace.file.read.text' @{workspace_id=$scope; path='fixtures/missing.txt'} -ExpectFailure
    Write-Text 'fixtures/missing.txt' 'recovered after observing missing input'
    Check 'Missing-file failure followed by successful recovery' ((Read-Text 'fixtures/missing.txt') -ceq 'recovered after observing missing input')

    $null = Invoke-Tool 'galaxyssi.workspace.file.write.text' @{workspace_id=$scope; path='../outside.txt'; text='must not escape'} -ExpectFailure
    Check 'Path traversal rejected' $true

    $bundle = Invoke-Tool 'galaxyssi.workspace.zip.create' @{workspace_id=$scope; archive_path='fixtures/bundle.zip';
        source_paths=@('fixtures/report.md','fixtures/budget.csv'); create_parents=$true}
    $listed = Invoke-Tool 'galaxyssi.workspace.zip.list' @{workspace_id=$scope; archive_path='fixtures/bundle.zip'}
    Check 'Document bundle created and reopened' ($listed.output.entries.Count -eq 2)

    $export = Invoke-Tool 'galaxyssi.workspace.file.export' @{workspace_id=$scope; path='fixtures/report.md'}
    $artifact = $export.output.artifacts[0]
    Check 'Export supplies hash-bound openability evidence' ($artifact.openability.status -eq 'verified' -and
        $artifact.sha256 -eq $artifact.openability.sha256 -and $artifact.relative_path -eq 'fixtures/report.md')
    Write-Text 'fixtures/report.md' 'changed draft'
    $secondExport = Invoke-Tool 'galaxyssi.workspace.file.export' @{workspace_id=$scope; path='fixtures/report.md'}
    Check 'Edited source produces a separate delivery version' ($secondExport.output.artifacts[0].sha256 -ne $artifact.sha256 -and
        $secondExport.output.artifacts[0].host_path -ne $artifact.host_path)
} catch { $failure = $_.Exception.Message }
finally {
    try {
        $null = Invoke-Tool 'galaxyssi.workspace.entry.delete' @{workspace_id=$scope; path='fixtures'; recursive=$true}
        $null = Invoke-Tool 'galaxyssi.workspace.entry.delete' @{workspace_id=$scope; path='.galaxyssi-artifacts'; recursive=$true}
        $cleanup = $true
    } catch { Write-Warning "Test fixture cleanup not confirmed: $($_.Exception.Message)" }
    $null = New-Item -ItemType Directory -Path $ReportDirectory -Force
    $path = Join-Path $ReportDirectory "$scope.json"
    [pscustomobject]@{ serial=$Serial; scope=$scope; passed=($null -eq $failure); failure=$failure;
        validation_layer='real phone native tools, not a model-planned end-to-end pass'; checks=@($checks.ToArray());
        cleanup_verified=$cleanup; completed_at=[DateTimeOffset]::Now.ToString('o'); steps=@($rows.ToArray()) } |
        ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $path -Encoding utf8
    Write-Host "Report: $path"
}
if ($failure) { throw $failure }
