param(
    [string]$Adb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe",
    [string]$Serial = 'R52R90282TY',
    [string]$Sqlite = 'sqlite3'
)
$ErrorActionPreference = 'Stop'
$model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Serial -ne 'R52R90282TY' -or $model -ne 'SM-T575') { throw 'Unexpected test device' }
$fixture = 'test-knowledge-source-replace-621d79d8-9ce1-4d12-95b8-ebde10511a3f.db'
$root = Join-Path (Get-Location) ('build/knowledge-primary-metadata-audit/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
# Call only after instrumentation finishes. A stopped process makes the DB/WAL copy coherent.
& $Adb -s $Serial shell am force-stop com.galaxyssi.chat
if ($LASTEXITCODE -ne 0) { throw 'Could not quiesce the test application' }
function Copy-TestDatabaseFile([string]$Suffix) {
    if ($Suffix -notin @('', '-wal')) { throw 'Unexpected SQLite suffix' }
    $remote = "databases/$fixture$Suffix"
    $null = & $Adb -s $Serial shell run-as com.galaxyssi.chat test -f $remote
    if ($LASTEXITCODE -ne 0) {
        if ($Suffix -eq '') { throw 'Retained test database is missing' }
        return
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Adb
    $info.Arguments = "-s $Serial exec-out run-as com.galaxyssi.chat cat $remote"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $errorOutput = $process.StandardError.ReadToEndAsync()
        $file = [System.IO.File]::Open((Join-Path $root "$fixture$Suffix"), [System.IO.FileMode]::CreateNew)
        try { $process.StandardOutput.BaseStream.CopyTo($file) } finally { $file.Dispose() }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Test database copy failed: $($errorOutput.Result)" }
    } finally { $process.Dispose() }
}
Copy-TestDatabaseFile ''
Copy-TestDatabaseFile '-wal'
$copy = Join-Path $root $fixture
$check = (& $Sqlite -readonly $copy 'PRAGMA integrity_check;' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $check -ne 'ok') { throw 'Copied catalog failed integrity_check' }
$sql = "SELECT (SELECT user_version FROM pragma_user_version) AS schema," +
    "count(*) AS records,sum(CASE WHEN length(header)=69 AND substr(header,1,5)='khp1:' " +
    "AND substr(header,6) NOT GLOB '*[^a-f0-9]*' THEN 1 ELSE 0 END) AS partitioned_headers," +
    "(SELECT count(*) FROM knowledge_primary_refs) AS primary_references," +
    "(SELECT count(*) FROM knowledge_primary_refs r LEFT JOIN knowledge_items i ON r.item_key=i.item_key " +
    "WHERE i.item_key IS NULL) AS orphan_references," +
    "(SELECT count(*) FROM knowledge_primary_partitions) AS registered_partitions FROM knowledge_items;"
$json = & $Sqlite -readonly -json $copy $sql
if ($LASTEXITCODE -ne 0) { throw 'Copied catalog query failed' }
$result = @($json | ConvertFrom-Json)[0]
if ($result.schema -ne 17 -or $result.records -ne 10001 -or $result.partitioned_headers -ne 10001 -or
    $result.primary_references -ne 10001 -or $result.orphan_references -ne 0 -or $result.registered_partitions -lt 1) {
    throw "Retained primary metadata audit failed: $json"
}
$summary = [ordered]@{device=$Serial;model=$model;fixture=$fixture;integrity=$check;catalog=$result}
$summary | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $root 'summary.json')
$summary | ConvertTo-Json -Depth 4
Write-Output "Verified retained metadata catalog. Evidence: $root"
