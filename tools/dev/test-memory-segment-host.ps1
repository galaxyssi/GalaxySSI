param(
    [string]$Java = (Get-Command java -ErrorAction Stop).Source,
    [string]$OutputDirectory = 'build/memory-segment-host'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$cache = Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1'
function CachedJar([string]$Group, [string]$Name, [string]$Version = '') {
    $path = Join-Path $cache "$Group/$Name/$Version"
    $jar = Get-ChildItem -LiteralPath $path -Recurse -Filter '*.jar' |
        Where-Object { $_.Name -notmatch 'sources|javadoc' } | Select-Object -First 1
    if (!$jar) { throw "Missing cached dependency: $path" }
    $jar.FullName
}
Push-Location $root
try {
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $stdlib = CachedJar 'org.jetbrains.kotlin' 'kotlin-stdlib' '2.0.21'
    $annotations = CachedJar 'org.jetbrains' 'annotations'
    $runtime = @($stdlib, $annotations, (CachedJar 'junit' 'junit' '4.13.2'),
        (CachedJar 'org.hamcrest' 'hamcrest-core' '1.3')) -join [IO.Path]::PathSeparator
    $compiler = @((CachedJar 'org.jetbrains.kotlin' 'kotlin-compiler-embeddable' '2.0.21'), $stdlib,
        (CachedJar 'org.jetbrains.kotlin' 'kotlin-script-runtime' '2.0.21'),
        (CachedJar 'org.jetbrains.kotlin' 'kotlin-reflect'), (CachedJar 'org.jetbrains.intellij.deps' 'trove4j'),
        (CachedJar 'org.jetbrains.kotlinx' 'kotlinx-coroutines-core-jvm'), $annotations) -join [IO.Path]::PathSeparator
    $names = @('MemorySegmentFile', 'MemorySegmentCopy', 'MemorySegmentAccess', 'MemorySegmentSweep', 'BackupRecordStream')
    $sources = @($names | ForEach-Object { "apps/android/app/src/main/java/com/galaxyssi/chat/$_.kt" })
    $tests = @($names | ForEach-Object { "${_}Test" }) + 'MemorySegmentAccessProcessTest'
    $sources += @($tests | ForEach-Object { "apps/android/app/src/test/java/com/galaxyssi/chat/$_.kt" })
    $jar = Join-Path $OutputDirectory 'tests.jar'
    $compileLog = Join-Path $OutputDirectory 'compile.log'
    & $Java -Xmx2g -cp $compiler org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect `
        -jvm-target 17 -classpath $runtime -d $jar @sources *> $compileLog
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $compileLog; throw 'Host compilation failed' }
    $log = Join-Path $OutputDirectory 'tests.log'
    $classes = @($tests | ForEach-Object { "com.galaxyssi.chat.$_" })
    & $Java -cp "$jar$([IO.Path]::PathSeparator)$runtime" org.junit.runner.JUnitCore @classes *> $log
    $code = $LASTEXITCODE
    Get-Content -LiteralPath $log
    if ($code -ne 0) { throw 'Memory segment host tests failed' }
} finally { Pop-Location }
