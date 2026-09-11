param(
    [ValidateSet('host', 'android')][string]$Mode = 'host',
    [string]$CargoHome,
    [string]$RustupHome,
    [string]$Ndk = "$env:LOCALAPPDATA\Android\Sdk\ndk\29.0.13113456",
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = 'R52R90282TY'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (!$CargoHome) { $CargoHome = Join-Path $root 'build/native-memory-deps/cargo' }
if (!$RustupHome) { $RustupHome = Join-Path $root 'build/native-memory-deps/rustup' }
$env:CARGO_HOME = $CargoHome
$env:RUSTUP_HOME = $RustupHome
$env:PATH = "$CargoHome\bin;$env:PATH"
$cargo = Join-Path $CargoHome 'bin/cargo.exe'
$manifest = Join-Path $root 'apps/android/memory-native/Cargo.toml'
$llvm = Join-Path $Ndk 'toolchains/llvm/prebuilt/windows-x86_64/bin'
$toolchain = '+1.97.1-x86_64-pc-windows-gnu'
if (!(Test-Path -LiteralPath $cargo) -or !(Test-Path -LiteralPath "$llvm/llvm-dlltool.exe")) {
    throw 'Install the pinned Rust toolchain and NDK described in apps/android/memory-native/README.md first.'
}
$id = [guid]::NewGuid().ToString('N')
$output = Join-Path $root "build/memory-native-evidence/$id"
New-Item -ItemType Directory -Force -Path $output | Out-Null
if ($Mode -eq 'host') {
    $env:CARGO_ENCODED_RUSTFLAGS = '-C' + [char]31 + "dlltool=$llvm/llvm-dlltool.exe"
    & $cargo $toolchain fmt --manifest-path $manifest --check
    if ($LASTEXITCODE -ne 0) { throw 'Native memory formatting check failed' }
    & $cargo $toolchain test --locked --offline --all-features --manifest-path $manifest --jobs 2 -- --show-output *> "$output/host.log"
    $code = $LASTEXITCODE
    Get-Content -LiteralPath "$output/host.log" -Tail 50
    if ($code -ne 0) { throw "Host regression failed: $output" }
} else {
    $model = (& $Adb -s $Serial shell getprop ro.product.model | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $model -ne 'SM-T575') { throw "Only SM-T575 is authorized for this probe; found $model" }
    $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "$llvm/aarch64-linux-android26-clang.cmd"
    $env:CARGO_ENCODED_RUSTFLAGS = @('-C', 'link-arg=-Wl,-z,max-page-size=16384', '-C', 'link-arg=-Wl,-z,common-page-size=16384') -join [char]31
    & $cargo $toolchain build --release --locked --offline --target aarch64-linux-android --features probe `
        --bin memory-native-probe --manifest-path $manifest --jobs 2 *> "$output/android-build.log"
    if ($LASTEXITCODE -ne 0) { throw "Android native build failed: $output" }
    $metadata = & $cargo $toolchain metadata --format-version 1 --no-deps --locked --offline --manifest-path $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Unable to locate the native target directory' }
    $targetDirectory = ($metadata | ConvertFrom-Json).target_directory
    $binary = Join-Path $targetDirectory 'aarch64-linux-android/release/memory-native-probe'
    $headers = & "$llvm/llvm-readelf.exe" --program-headers --wide $binary
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read native ELF headers' }
    $headers | Set-Content -Encoding utf8 -LiteralPath "$output/elf-headers.txt"
    $loads = @($headers | Where-Object { $_ -match '^\s*LOAD\s' })
    if ($loads.Count -eq 0) { throw 'No ELF load segments found' }
    foreach ($line in $loads) {
        $fields = $line.Trim() -split '\s+'
        $offset = [Convert]::ToInt64($fields[1], 16)
        $address = [Convert]::ToInt64($fields[2], 16)
        $alignment = [Convert]::ToInt64($fields[-1], 16)
        if ($alignment -lt 16384 -or $offset % 16384 -ne $address % 16384) { throw "Invalid 16KiB ELF segment: $line" }
    }
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash.ToLowerInvariant()
    $sha | Set-Content -Encoding ascii -LiteralPath "$output/binary.sha256"
    $fixture = "/data/local/tmp/galaxyssi-native-memory-$id"
    $remote = "$fixture-bin"
    & $Adb -s $Serial push $binary $remote
    if ($LASTEXITCODE -ne 0) { throw 'Native probe upload failed' }
    & $Adb -s $Serial shell chmod 700 $remote
    if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare native probe executable' }
    $phases = @('prepare', 'verify', 'wrong-key', 'corrupt', 'verify')
    for ($i = 0; $i -lt $phases.Count; $i++) {
        $phase = $phases[$i]
        $result = & $Adb -s $Serial shell $remote $phase $fixture 2>&1
        $code = $LASTEXITCODE
        $result | Set-Content -Encoding utf8 -LiteralPath "$output/$i-$phase.log"
        Write-Output $result
        $expected = switch ($phase) {
            'prepare' { 'prepared count=64' }
            'verify' { 'verified persisted_encrypted_vectors=64' }
            'wrong-key' { 'wrong_key_rejected' }
            'corrupt' { 'corruption_rejected_original_restored' }
        }
        if ($code -ne 0 -or ($result | Out-String) -notmatch [regex]::Escape($expected)) {
            throw "Native probe failed in $phase. Evidence: $output"
        }
    }
    Write-Output "Verified ARM64 probe and $($loads.Count) aligned ELF segments; sha256=$sha"
    Write-Output "Synthetic fixture retained at $fixture; no App database or model was accessed."
}
Write-Output "Native memory evidence: $output"
