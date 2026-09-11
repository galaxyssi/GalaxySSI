import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
function argument(name) {
  const i = process.argv.indexOf(name);
  if (i < 0 || !process.argv[i + 1]) throw new Error(`Missing ${name}`);
  return path.resolve(process.argv[i + 1]);
}
const sdk = argument("--sdk");
const output = argument("--output");
const windows = process.platform === "win32";
const host = windows ? "windows-x86_64" : process.platform === "darwin" ? "darwin-x86_64" : "linux-x86_64";
const suffix = windows ? ".exe" : "";
const cached = path.join(root, "build/native-memory-deps");
const homes = [process.env.CARGO_HOME, path.join(cached, "cargo"), path.join(homedir(), ".cargo")].filter(Boolean);
const cargoHome = homes.find(p => existsSync(path.join(p, `bin/cargo${suffix}`)));
if (!cargoHome) throw new Error("Install Rust 1.97.1 with the aarch64-linux-android target; see apps/android/memory-native/README.md");
const llvm = path.join(sdk, "ndk/29.0.13113456/toolchains/llvm/prebuilt", host, "bin");
const clang = path.join(llvm, `aarch64-linux-android26-clang${windows ? ".cmd" : ""}`);
if (!existsSync(clang)) throw new Error("Android NDK 29.0.13113456 is required for the native memory library");
const manifest = path.join(root, "apps/android/memory-native/Cargo.toml");
const toolchain = windows ? "+1.97.1-x86_64-pc-windows-gnu" : "+1.97.1";
const env = {
  ...process.env,
  CARGO_HOME: cargoHome,
  ...(cargoHome === path.join(cached, "cargo") && !process.env.RUSTUP_HOME ? { RUSTUP_HOME: path.join(cached, "rustup") } : {}),
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER: clang,
  CC_aarch64_linux_android: clang,
  AR_aarch64_linux_android: path.join(llvm, `llvm-ar${suffix}`),
  LIBSQLITE3_FLAGS: "-DSQLITE_MAX_ATTACHED=64",
  CARGO_ENCODED_RUSTFLAGS: ["-C", "link-arg=-Wl,-z,max-page-size=16384", "-C", "link-arg=-Wl,-z,common-page-size=16384"].join("\x1f"),
};
const cargo = path.join(cargoHome, `bin/cargo${suffix}`);
const options = { cwd: root, env, windowsHide: true };
execFileSync(cargo, [toolchain, "build", "--release", "--locked", ...(process.argv.includes("--offline") ? ["--offline"] : []),
  "--lib", "--features", "android-jni", "--target", "aarch64-linux-android", "--manifest-path", manifest, "--jobs", "2"],
  { ...options, stdio: "inherit" });
const metadata = JSON.parse(execFileSync(cargo, [toolchain, "metadata", "--no-deps", "--format-version", "1", "--locked", "--offline",
  "--manifest-path", manifest], { ...options, encoding: "utf8" }));
const library = path.join(metadata.target_directory, "aarch64-linux-android/release/libgalaxyssi_memory_native.so");
const headers = execFileSync(path.join(llvm, `llvm-readelf${suffix}`), ["--program-headers", "--wide", library], { ...options, encoding: "utf8" });
const segments = headers.split(/\r?\n/).filter(line => /^\s*LOAD\s/.test(line));
if (!segments.length) throw new Error("Native memory library has no ELF LOAD segments");
for (const segment of segments) {
  const fields = segment.trim().split(/\s+/);
  const offset = Number.parseInt(fields[1], 16), address = Number.parseInt(fields[2], 16), alignment = Number.parseInt(fields.at(-1), 16);
  if (alignment < 16384 || offset % 16384 !== address % 16384) throw new Error(`Unaligned native memory segment: ${segment}`);
}
const destination = path.join(output, "arm64-v8a");
mkdirSync(destination, { recursive: true });
copyFileSync(library, path.join(destination, path.basename(library)));
console.log(`Native memory JNI staged with ${segments.length} aligned ELF LOAD segments`);
