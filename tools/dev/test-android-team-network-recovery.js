const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

const options = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, args) => {
  if (value.startsWith("--")) pairs.push([value.slice(2), args[index + 1]]);
  return pairs;
}, []));
const serial = options.serial;
if (!serial || serial.startsWith("--")) throw new Error("Explicit --serial is required; never select another device automatically");
const outageMs = Number(options["outage-seconds"] || 600) * 1000;
const dozeMs = Number(options["doze-seconds"] || 180) * 1000;
if (!Number.isFinite(outageMs) || outageMs < 60000 || outageMs > 3600000 ||
    !Number.isFinite(dozeMs) || dozeMs < 30000 || dozeMs >= outageMs) {
  throw new Error("Use a 60-3600 second outage and a shorter Doze interval of at least 30 seconds");
}
const adb = process.env.ADB || "adb";
const target = ["-P", options.port || "5037", "-s", serial];
const app = "com.galaxyssi.chat";
const remoteReport = `/sdcard/Android/data/${app}/files/agent-team-network-recovery-report.json`;
const output = path.resolve(options.output || path.join(os.tmpdir(), `galaxyssi-network-${Date.now()}`));
fs.mkdirSync(output, { recursive: true });
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
function run(args, optional = false) {
  const result = spawnSync(adb, [...target, ...args], { encoding: "utf8", windowsHide: true, timeout: 20000 });
  if (result.error || result.status !== 0) {
    if (optional) return "";
    throw result.error || new Error(`adb ${args.join(" ")}: ${result.stderr || result.stdout}`);
  }
  return result.stdout.trim();
}
function report() {
  try { return JSON.parse(run(["shell", "cat", remoteReport], true)); } catch { return null; }
}
function deepState() { return run(["shell", "dumpsys", "deviceidle", "get", "deep"]); }
let child;
let childResult;
let instrumentOutput = "";
let wifi;
let mobile;
let changed = false;
const timeline = [];
function record(event, extra = {}) {
  const item = { event, time: new Date().toISOString(), ...extra };
  timeline.push(item);
  process.stdout.write(`${JSON.stringify(item)}\n`);
  fs.writeFileSync(path.join(output, "host-timeline.json"), JSON.stringify(timeline, null, 2));
}
function restore() {
  if (!changed) return;
  const errors = [];
  const commands = [
    ["shell", "dumpsys", "deviceidle", "unforce"],
    ["shell", "dumpsys", "battery", "reset"],
    ["shell", "svc", "wifi", wifi === "1" ? "enable" : "disable"],
    ["shell", "svc", "data", mobile === "1" ? "enable" : "disable"],
    ["shell", "input", "keyevent", "224"],
  ];
  for (const command of commands) {
    try { run(command); } catch (error) { errors.push(error.message); }
  }
  changed = errors.length > 0;
  record("settings_restored", { errors });
  if (errors.length) throw new Error(errors.join("\n"));
}
process.on("SIGINT", () => { try { restore(); } finally { child?.kill(); process.exit(130); } });
process.on("SIGTERM", () => { try { restore(); } finally { child?.kill(); process.exit(143); } });

async function main() {
  if (run(["get-state"]) !== "device") throw new Error("Selected device is not authorized");
  wifi = run(["shell", "settings", "get", "global", "wifi_on"]);
  mobile = run(["shell", "settings", "get", "global", "mobile_data"]);
  if (![wifi, mobile].every((value) => ["0", "1"].includes(value)) || (wifi === "0" && mobile === "0")) {
    throw new Error("Need a known enabled network state to restore");
  }
  if (!run(["shell", "dumpsys", "deviceidle"]).includes("mForceIdle=false") ||
      run(["shell", "dumpsys", "battery"]).includes("UPDATES STOPPED")) {
    throw new Error("Refusing to overwrite an existing idle/battery simulation");
  }
  const previous = report()?.fixture_id;
  record("baseline", { serial, wifi, mobile, deep: deepState(), outage_ms: outageMs, doze_ms: dozeMs });
  changed = true;
  run(["shell", "svc", "wifi", "disable"]);
  run(["shell", "svc", "data", "disable"]);
  await delay(5000);
  child = spawn(adb, [...target, "shell", "am", "instrument", "-w", "-r",
    "-e", "class", `${app}.AgentTeamNetworkRecoveryDeviceTest`,
    "-e", "network_fault_test", "true", "-e", "minimum_outage_ms", String(outageMs),
    `${app}.test/androidx.test.runner.AndroidJUnitRunner`], { windowsHide: true });
  child.stdout.on("data", (data) => { instrumentOutput += data; });
  child.stderr.on("data", (data) => { instrumentOutput += data; });
  child.on("error", (error) => { instrumentOutput += error.stack; childResult = -1; });
  child.on("close", (code) => { childResult = code; });
  const readyDeadline = Date.now() + 60000;
  let ready;
  while (Date.now() < readyDeadline) {
    ready = report();
    if (ready?.fixture_id !== previous && ready?.phase === "waiting") break;
    if (childResult !== undefined) throw new Error(`Instrumentation ended before readiness: ${instrumentOutput}`);
    await delay(1000);
  }
  if (!ready || ready.fixture_id === previous || ready.phase !== "waiting") throw new Error("No fresh ready fixture");
  const start = Date.now();
  record("offline_fixture_ready", ready);
  run(["shell", "input", "keyevent", "3"]);
  run(["shell", "dumpsys", "battery", "unplug"]);
  run(["shell", "input", "keyevent", "223"]);
  run(["shell", "dumpsys", "deviceidle", "force-idle", "deep"]);
  if (deepState() !== "IDLE") throw new Error("Device did not enter deep idle");
  record("doze_entered", { deep: deepState() });
  let leftDoze = false;
  while (Date.now() - start < outageMs + 1000) {
    if (childResult !== undefined) throw new Error(`Instrumentation stopped during outage: ${instrumentOutput}`);
    if (!leftDoze && Date.now() - start >= dozeMs) {
      run(["shell", "dumpsys", "deviceidle", "unforce"]);
      run(["shell", "dumpsys", "battery", "reset"]);
      leftDoze = true;
      record("doze_released_network_still_offline", { deep: deepState() });
    }
    record("outage_sample", { deep: deepState(), fixture: report() });
    await delay(30000);
  }
  restore();
  record("network_restored", { wifi: run(["shell", "settings", "get", "global", "wifi_on"]),
    mobile: run(["shell", "settings", "get", "global", "mobile_data"]) });
  const resultDeadline = Date.now() + 180000;
  while (childResult === undefined && Date.now() < resultDeadline) await delay(1000);
  if (childResult === undefined) throw new Error("Recovery instrumentation timed out");
  const result = report();
  fs.writeFileSync(path.join(output, "device-report.json"), JSON.stringify(result, null, 2));
  if (childResult !== 0 || !/OK \(1 test\)/.test(instrumentOutput) || result?.phase !== "passed") {
    throw new Error(`Fault matrix failed: ${instrumentOutput}`);
  }
  record("passed", result);
}
main().catch((error) => { process.stderr.write(`${error.stack}\n`); process.exitCode = 1; }).finally(() => {
  try { restore(); } catch (error) { process.stderr.write(`${error.stack}\n`); process.exitCode = 1; }
  if (child && childResult === undefined) child.kill();
  fs.writeFileSync(path.join(output, "instrumentation.log"), instrumentOutput);
  process.stdout.write(`Reports: ${output}\n`);
});
