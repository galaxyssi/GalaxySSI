param(
    [string]$Java = (Get-Command java -ErrorAction Stop).Source,
    [string]$Python = (Get-Command python -ErrorAction Stop).Source,
    [string]$OutputDirectory = 'build/vector-feed-host'
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
    $runtime = @($stdlib, $annotations) -join [IO.Path]::PathSeparator
    $compiler = @((CachedJar 'org.jetbrains.kotlin' 'kotlin-compiler-embeddable' '2.0.21'), $stdlib,
        (CachedJar 'org.jetbrains.kotlin' 'kotlin-script-runtime' '2.0.21'),
        (CachedJar 'org.jetbrains.kotlin' 'kotlin-reflect'), (CachedJar 'org.jetbrains.intellij.deps' 'trove4j'),
        (CachedJar 'org.jetbrains.kotlinx' 'kotlinx-coroutines-core-jvm'), $annotations) -join [IO.Path]::PathSeparator
    $jar = Join-Path $OutputDirectory 'schema.jar'
    & $Java -Xmx512m -cp $compiler org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect `
        -jvm-target 17 -classpath $runtime -d $jar `
        apps/android/app/src/main/java/com/galaxyssi/chat/KnowledgeVectorChangeSchema.kt `
        tools/dev/fixtures/vector-feed/SchemaEmitter.kt *> "$OutputDirectory/compile.log"
    if ($LASTEXITCODE -ne 0) { Get-Content "$OutputDirectory/compile.log"; throw 'Schema compilation failed' }
    & $Java -cp "$jar$([IO.Path]::PathSeparator)$runtime" com.galaxyssi.chat.SchemaEmitterKt > "$OutputDirectory/schema.base64"
    if ($LASTEXITCODE -ne 0) { throw 'Schema emitter failed' }
    & $Python tools/dev/test-vector-feed-schema.py "$OutputDirectory/schema.base64" *> "$OutputDirectory/tests.log"
    $code = $LASTEXITCODE
    Get-Content "$OutputDirectory/tests.log"
    if ($code -ne 0) { throw 'Vector feed host verification failed' }
} finally { Pop-Location }
