param(
    [Parameter(Mandatory)][ValidateSet('build', 'grow', 'measure')][string]$Mode,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Label,
    [ValidatePattern('^[a-z0-9-]+$')][string]$Fixture = 'ann-v1',
    [ValidateRange(64, [long]::MaxValue)][long]$Rows = 1024,
    [ValidateRange(1, 64)][int]$Batch = 64,
    [string]$Serial = 'R52R90282TY'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk'
$adb = Join-Path $sdk 'platform-tools/adb.exe'
$llvm = Join-Path $sdk 'ndk/29.0.13113456/toolchains/llvm/prebuilt/windows-x86_64/bin'
$directory = Join-Path $root "build/native-memory-scale/$Label"
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$binary = Join-Path $directory 'memory-native-scale'
$run = [guid]::NewGuid().ToString('N')
$log = Join-Path $directory "$Fixture-$Mode-$Rows-$run.log"
if ($Mode -eq 'build') {
    if (Test-Path -LiteralPath $binary) { throw "Label '$Label' already has a frozen binary; choose a new label" }
    $env:CARGO_HOME = Join-Path $root 'build/native-memory-deps/cargo'
    $env:RUSTUP_HOME = Join-Path $root 'build/native-memory-deps/rustup'
    $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "$llvm/aarch64-linux-android26-clang.cmd"
    $env:CC_aarch64_linux_android = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
    $env:AR_aarch64_linux_android = "$llvm/llvm-ar.exe"
    $env:LIBSQLITE3_FLAGS = '-DSQLITE_MAX_ATTACHED=64'
    $env:CARGO_ENCODED_RUSTFLAGS = @('-C', 'link-arg=-Wl,-z,max-page-size=16384', '-C', 'link-arg=-Wl,-z,common-page-size=16384') -join [char]31
    $cargo = Join-Path $env:CARGO_HOME 'bin/cargo.exe'
    $manifest = Join-Path $root 'apps/android/memory-native/Cargo.toml'
    & $cargo +1.97.1-x86_64-pc-windows-gnu fmt --manifest-path $manifest --check
    if ($LASTEXITCODE -ne 0) { throw 'Native formatting failed' }
    & $cargo +1.97.1-x86_64-pc-windows-gnu build --release --locked --offline --target aarch64-linux-android `
        --features sqlite-store --bin memory-native-scale --manifest-path $manifest --jobs 2 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw "Native scale build failed: $log" }
    $metadata = & $cargo +1.97.1-x86_64-pc-windows-gnu metadata --format-version 1 --no-deps --offline --manifest-path $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate native target directory' }
    $source = Join-Path ($metadata | ConvertFrom-Json).target_directory 'aarch64-linux-android/release/memory-native-scale'
    Copy-Item -LiteralPath $source -Destination $binary
    $headers = & "$llvm/llvm-readelf.exe" --program-headers --wide $binary
    if ($LASTEXITCODE -ne 0) { throw 'Cannot validate ELF alignment' }
    $loads = @($headers | Where-Object { $_ -match '^\s*LOAD\s' })
    if (!$loads.Count) { throw 'No ELF LOAD segments' }
    foreach ($line in $loads) {
        $f = $line.Trim() -split '\s+'
        if ([Convert]::ToInt64($f[-1], 16) -lt 16384 -or
            [Convert]::ToInt64($f[1], 16) % 16384 -ne [Convert]::ToInt64($f[2], 16) % 16384) { throw "Unaligned segment: $line" }
    }
    Get-FileHash -Algorithm SHA256 -LiteralPath $binary
} else {
    $model = (& $adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $model -ne 'SM-T575') { throw "Only SM-T575 is authorized; found $model" }
    if (!(Test-Path -LiteralPath $binary)) { throw "Build the '$Label' binary first" }
    $remote = "/data/local/tmp/galaxyssi-native-scale-$Label-bin"
    & $adb -s $Serial push $binary $remote
    if ($LASTEXITCODE -ne 0) { throw 'Native scale upload failed' }
    & $adb -s $Serial shell chmod 700 $remote
    if ($LASTEXITCODE -ne 0) { throw 'Cannot execute native scale probe' }
    & $adb -s $Serial shell $remote $Mode "/data/local/tmp/galaxyssi-native-scale-$Fixture" $Rows $Batch 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw "Native scale run failed: $log" }
}
Write-Output "Native scale evidence: $log"
