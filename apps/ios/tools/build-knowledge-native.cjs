const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function run(command, args, env, capture = false) {
  const result = spawnSync(command, args, { env, encoding: 'utf8',
    stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})`);
  return capture ? result.stdout.trim() : '';
}

function build() {
  if (process.platform !== 'darwin') throw new Error('Native iOS memory requires Xcode on macOS');
  const env = { ...process.env };
  const sdk = env.PLATFORM_NAME;
  if (!['iphoneos', 'iphonesimulator'].includes(sdk)) throw new Error(`Unsupported iOS platform: ${sdk}`);
  for (const name of ['SRCROOT', 'DERIVED_FILE_DIR', 'BUILT_PRODUCTS_DIR']) {
    if (!env[name] || !path.isAbsolute(env[name])) throw new Error(`Missing absolute ${name}`);
  }
  const crate = path.join(env.SRCROOT, 'memory-native');
  const exportsFile = path.join(crate, 'exports.txt');
  if (exportsFile.includes(',')) throw new Error('Native linker export-list path must not contain commas');
  const framework = path.join(env.BUILT_PRODUCTS_DIR, 'GalaxySSIMemory.framework');
  const output = path.join(framework, 'GalaxySSIMemory');
  const arches = [...new Set((env.ARCHS || '').trim().split(/\s+/).filter(Boolean))];
  if (!arches.length) throw new Error('Xcode did not provide ARCHS');
  const targets = arches.map(arch => {
    if (arch === 'arm64') return sdk === 'iphoneos' ? 'aarch64-apple-ios' : 'aarch64-apple-ios-sim';
    if (arch === 'x86_64' && sdk === 'iphonesimulator') return 'x86_64-apple-ios';
    throw new Error(`Unsupported native memory architecture: ${sdk}/${arch}`);
  });
  const toolchain = '1.97.1';
  run('rustup', ['toolchain', 'install', toolchain, '--profile', 'minimal'], env);
  env.SDKROOT = run('xcrun', ['--sdk', sdk, '--show-sdk-path'], env, true);
  const clang = run('xcrun', ['--sdk', sdk, '--find', 'clang'], env, true);
  const ar = run('xcrun', ['--sdk', sdk, '--find', 'ar'], env, true);
  env.IPHONEOS_DEPLOYMENT_TARGET = '15.0';
  env.CARGO_TARGET_DIR = path.join(env.DERIVED_FILE_DIR, 'GalaxySSIMemoryRuntime', 'cargo');
  // Isolate bundled SQLite exports in the dynamic framework, never the App executable.
  delete env.RUSTFLAGS;
  env.CARGO_ENCODED_RUSTFLAGS = ['-C', 'link-arg=-Wl,-install_name,@rpath/GalaxySSIMemory.framework/GalaxySSIMemory',
    '-C', `link-arg=-Wl,-exported_symbols_list,${exportsFile}`].join('\x1f');
  const binaries = [];
  for (const target of targets) {
    run('rustup', ['target', 'add', '--toolchain', toolchain, target], env);
    const key = target.replaceAll('-', '_');
    env[`CARGO_TARGET_${key.toUpperCase()}_LINKER`] = clang;
    env[`CC_${key}`] = clang;
    env[`AR_${key}`] = ar;
    run('cargo', [`+${toolchain}`, 'build', '--manifest-path', path.join(crate, 'Cargo.toml'),
      '--locked', '--release', '--target', target], env);
    const binary = path.join(env.CARGO_TARGET_DIR, target, 'release', 'libGalaxySSIMemory.dylib');
    if (!fs.statSync(binary).isFile()) throw new Error(`Missing native memory binary: ${target}`);
    binaries.push(binary);
  }
  fs.mkdirSync(path.join(framework, 'Headers'), { recursive: true });
  fs.mkdirSync(path.join(framework, 'Modules'), { recursive: true });
  run('xcrun', ['lipo', '-create', ...binaries, '-output', output], env);
  run('xcrun', ['lipo', '-verify_arch', ...arches, output], env);
  fs.copyFileSync(path.join(crate, 'include', 'GalaxySSIMemory.h'), path.join(framework, 'Headers', 'GalaxySSIMemory.h'));
  fs.copyFileSync(path.join(crate, 'include', 'module.modulemap'), path.join(framework, 'Modules', 'module.modulemap'));
  fs.copyFileSync(path.join(crate, 'Info.plist'), path.join(framework, 'Info.plist'));
  if (sdk === 'iphonesimulator') {
    run('/usr/libexec/PlistBuddy', ['-c', 'Set :CFBundleSupportedPlatforms:0 iPhoneSimulator', path.join(framework, 'Info.plist')], env);
  }
  const exported = run('xcrun', ['dyld_info', '-exports', output], env, true);
  if (/_sqlite3_/.test(exported)) throw new Error('Bundled SQLite symbols escaped native memory framework');
  const expected = fs.readFileSync(exportsFile, 'utf8').trim().split(/\r?\n/);
  for (const symbol of expected) if (!exported.includes(symbol)) throw new Error(`Missing C ABI export ${symbol}`);
  console.log(`Built native memory framework for ${sdk}: ${arches.join(', ')}`);
}

if (require.main === module) {
  try { build(); } catch (error) { console.error(`error: ${error.message}`); process.exitCode = 1; }
}
