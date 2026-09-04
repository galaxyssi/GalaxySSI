const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { cases } = require("./android-agent-model-reply-cases");

const desktopRoot = path.resolve(__dirname, "..");
const packageName = "com.galaxyssi.chat";
const activityName = `${packageName}/.MainActivity`;
const defaultReportPath = path.join(
  desktopRoot,
  "build",
  "reports",
  "sm-g9880-agent-model-replies-100.json",
);

function parseOptions(argv) {
  const value = name => argv.find(arg => arg.startsWith(`${name}=`))?.slice(name.length + 1) || "";
  return {
    serial: value("--serial") || process.env.GALAXYSSI_ANDROID_SERIAL || "",
    reportPath: path.resolve(value("--report") || defaultReportPath),
    caseId: value("--case"),
    resume: argv.includes("--resume"),
    catalogOnly: argv.includes("--catalog-only"),
    timeoutMs: Number(value("--timeout-ms") || 180_000),
  };
}

function adb(serial, args, options = {}) {
  return execFileSync("adb", ["-s", serial, ...args], {
    cwd: desktopRoot,
    encoding: options.encoding || "utf8",
    windowsHide: true,
    timeout: options.timeout || 30_000,
    stdio: options.stdio || ["ignore", "pipe", "pipe"],
  });
}

function sleep(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

function decodeXml(value) {
  return String(value)
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function preferenceString(xml, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = String(xml).match(new RegExp(`<string name="${escaped}">([\\s\\S]*?)<\\/string>`));
  return match ? decodeXml(match[1]) : "";
}

function readSnapshot(serial, token) {
  let xml = "";
  try {
    xml = adb(serial, [
      "shell", "run-as", packageName,
      "grep", "-F", token,
      "shared_prefs/galaxyssi_debug_agent.xml",
    ], { timeout: 5_000 });
  } catch {
    return null;
  }
  const raw = preferenceString(xml, token);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function runAdbProperty(serial, name) {
  return adb(serial, ["shell", "getprop", name]).trim();
}

function installedVersion(serial) {
  const dump = adb(serial, ["shell", "dumpsys", "package", packageName]);
  return {
    versionName: dump.match(/versionName=([^\s]+)/)?.[1] || "",
    versionCode: dump.match(/versionCode=(\d+)/)?.[1] || "",
  };
}

async function fetchJson(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  return response.json();
}

async function preflight(options) {
  if (!options.serial) {
    throw new Error("Pass --serial=<SM-G9880 serial>; implicit ADB device selection is forbidden.");
  }
  const devices = execFileSync("adb", ["devices", "-l"], { encoding: "utf8", windowsHide: true });
  const line = devices.split(/\r?\n/).find(item => item.startsWith(`${options.serial} `));
  if (!line || !/\sdevice\s/.test(line)) throw new Error(`ADB device ${options.serial} is not connected and authorized.`);
  const model = runAdbProperty(options.serial, "ro.product.model");
  const device = runAdbProperty(options.serial, "ro.product.device");
  if (model.replaceAll("_", "-").toUpperCase() !== "SM-G9880" || device.toLowerCase() !== "z3q") {
    throw new Error(`This suite may run only on SM-G9880/z3q; actual model=${model}, device=${device}.`);
  }
  const appVersion = installedVersion(options.serial);
  if (!appVersion.versionName) throw new Error(`${packageName} is not installed on ${options.serial}.`);
  const [health, agentPayload] = await Promise.all([
    fetchJson("http://127.0.0.1:8765/health"),
    fetchJson("http://127.0.0.1:8765/api/agents"),
  ]);
  const agentList = Array.isArray(agentPayload) ? agentPayload : agentPayload.agents || [];
  const codex = agentList.find(agent => agent.id === "codex");
  if (!codex || !["ready", "online", "available"].includes(String(codex.status).toLowerCase())) {
    throw new Error(`Codex Agent is not ready: ${JSON.stringify(codex || agentPayload)}`);
  }
  return { model, device, appVersion, health, codex };
}

function forbiddenFallback(entries) {
  return entries.some(entry => {
    const dedupe = String(entry.dedupe_key || "");
    return dedupe.startsWith("fast-local:") ||
      dedupe.startsWith("direct-system:") ||
      dedupe.startsWith("skill-result:");
  });
}

function assess(testCase, snapshot, wallMs) {
  const entries = Array.isArray(snapshot?.entries) ? snapshot.entries : [];
  const user = entries.find(entry => entry.role === "USER");
  const assistant = [...entries].reverse().find(entry => entry.role === "ASSISTANT");
  const processEntries = entries.filter(entry => entry.role === "PROCESS");
  const processText = processEntries.map(entry => String(entry.text || ""));
  const response = String(assistant?.text || "").trim();
  const requiredMatched = testCase.requiredAny.some(required => response.includes(required));
  const requiresWeb = testCase.category === "web_search";
  const webRetrievalObserved = processText.some(text =>
    /(?:searching|searched|web search|search the web|联网|网页搜索|搜索网页|检索网页|浏览网页)/i.test(text),
  );
  const sourceLinks = response.match(/https?:\/\/[^\s)\]]+/g) || [];
  const codexStartedPattern = /(?:正在运行\s*Codex|Codex\s*·\s*.+正在规划手机任务)/i;
  const codexStarted = processText.some(text => codexStartedPattern.test(text));
  const codexCompleted = processText.some(text => /Codex\s*·\s*已完成/i.test(text));
  const modelFirstEvent = processEntries.find(entry =>
    codexStartedPattern.test(String(entry.text || "")),
  );
  const modelCompletedEvent = [...processEntries].reverse()
    .find(entry => /Codex\s*·\s*已完成/i.test(String(entry.text || "")));
  const modelMs = modelFirstEvent && modelCompletedEvent
    ? Math.max(0, modelCompletedEvent.timestamp - modelFirstEvent.timestamp)
    : null;
  const turnMs = user && assistant ? Math.max(0, assistant.timestamp - user.timestamp) : wallMs;
  const failureText = processEntries.find(entry => {
    const dedupe = String(entry.dedupe_key || "");
    if (dedupe.startsWith("voice-agent-first-discovery:")) return false;
    const text = String(entry.text || "").trim();
    return /^(任务|Codex|Agent|请求|执行|连接|工具).{0,24}(失败|已超时|无法连接|not verified|timed out|failed)$/i.test(text);
  })?.text || "";
  const checks = {
    complete: snapshot?.complete === true,
    phase_completed: snapshot?.phase === "COMPLETED",
    user_persisted: String(user?.text || "") === testCase.prompt,
    reply_non_empty: response.length > 0,
    marker_present: response.includes(testCase.marker),
    semantic_contract: requiredMatched,
    codex_started: codexStarted,
    codex_completed: codexCompleted,
    no_local_or_system_fallback: !forbiddenFallback(entries),
    final_bound_to_turn: String(assistant?.dedupe_key || "").startsWith("assistant-final:turn:"),
    no_terminal_failure: failureText === "",
    web_retrieval_observed: !requiresWeb || webRetrievalObserved,
    source_citation_present: !requiresWeb || sourceLinks.length > 0,
  };
  return {
    id: testCase.id,
    category: testCase.category,
    marker: testCase.marker,
    prompt: testCase.prompt,
    required_any: testCase.requiredAny,
    conversation_id: snapshot?.conversation_id || "",
    turn_id: snapshot?.turn_id || "",
    phase: snapshot?.phase || "",
    response,
    process: processText,
    started_at: snapshot?.started_at || 0,
    captured_at: snapshot?.captured_at || 0,
    wall_ms: wallMs,
    turn_ms: turnMs,
    model_ms: modelMs,
    failure_text: failureText,
    source_links: sourceLinks,
    checks,
    passed: Object.values(checks).every(Boolean),
  };
}

async function runCase(serial, testCase, timeoutMs) {
  const token = `smg9880_agent_${testCase.id}_${Date.now()}`;
  const started = Date.now();
  adb(serial, [
    "shell", "am", "start", "-n", activityName,
    "--es", "galaxyssi_debug_agent_goal_b64", Buffer.from(testCase.prompt, "utf8").toString("base64"),
    "--es", "galaxyssi_debug_agent_token", token,
    "--ez", "galaxyssi_debug_agent_new_conversation", "true",
  ]);
  let snapshot = null;
  while (Date.now() - started < timeoutMs) {
    await sleep(500);
    snapshot = readSnapshot(serial, token) || snapshot;
    if (snapshot?.complete) break;
  }
  return assess(testCase, snapshot, Date.now() - started);
}

function loadExisting(reportPath) {
  try {
    return JSON.parse(fs.readFileSync(reportPath, "utf8"));
  } catch {
    return null;
  }
}

function summarize(records) {
  const passed = records.filter(record => record.passed).length;
  const latencies = records.filter(record => record.passed).map(record => record.turn_ms).sort((a, b) => a - b);
  const percentile = ratio => latencies.length
    ? latencies[Math.min(latencies.length - 1, Math.floor((latencies.length - 1) * ratio))]
    : null;
  return {
    passed,
    failed: records.length - passed,
    total: records.length,
    p50_turn_ms: percentile(0.5),
    p95_turn_ms: percentile(0.95),
    max_turn_ms: latencies.at(-1) ?? null,
  };
}

function saveReport(reportPath, report) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  const temporary = `${reportPath}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(report, null, 2)}\n`);
  fs.renameSync(temporary, reportPath);
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  if (cases.length !== 100) throw new Error(`Expected exactly 100 cases, found ${cases.length}.`);
  if (options.catalogOnly) {
    process.stdout.write(`${JSON.stringify({ total: cases.length, categories: [...new Set(cases.map(item => item.category))] })}\n`);
    return;
  }
  const environment = await preflight(options);
  const selected = options.caseId ? cases.filter(item => item.id === options.caseId) : cases;
  if (!selected.length) throw new Error(`Unknown case ${options.caseId}.`);
  const existing = options.resume ? loadExisting(options.reportPath) : null;
  const recordsById = new Map((existing?.records || []).map(record => [record.id, record]));
  const report = {
    schema_version: 1,
    suite: "sm-g9880-real-agent-model-replies-100",
    generated_at: new Date().toISOString(),
    completed_at: "",
    device: {
      serial: options.serial,
      model: environment.model,
      product_device: environment.device,
      app_version_name: environment.appVersion.versionName,
      app_version_code: environment.appVersion.versionCode,
    },
    agent: {
      id: "codex",
      name: environment.codex.name || "Codex Agent",
      status: environment.codex.status,
      adapter_type: environment.codex.adapter_type || environment.codex.adapter?.adapter_type || "",
      desktop_connector: environment.health.connector?.name || environment.health.connector_name || "GalaxySSI Desktop",
    },
    records: [...recordsById.values()],
    summary: summarize([...recordsById.values()]),
  };
  saveReport(options.reportPath, report);

  for (const testCase of selected) {
    if (options.resume && recordsById.get(testCase.id)?.passed) {
      process.stdout.write(`[${testCase.id}/100] resume: already passed\n`);
      continue;
    }
    process.stdout.write(`[${testCase.id}/100] ${testCase.category}: sending through SM-G9880 Agent Loop\n`);
    const record = await runCase(options.serial, testCase, options.timeoutMs);
    recordsById.set(testCase.id, record);
    report.records = [...recordsById.values()].sort((left, right) => left.id.localeCompare(right.id));
    report.summary = summarize(report.records);
    report.generated_at = new Date().toISOString();
    saveReport(options.reportPath, report);
    process.stdout.write(`${JSON.stringify({
      id: record.id,
      passed: record.passed,
      turn_ms: record.turn_ms,
      model_ms: record.model_ms,
      conversation_id: record.conversation_id,
      response: record.response,
      failed_checks: Object.entries(record.checks).filter(([, ok]) => !ok).map(([name]) => name),
    })}\n`);
  }

  report.completed_at = new Date().toISOString();
  report.summary = summarize(report.records);
  const expectedIds = new Set(selected.map(item => item.id));
  const selectedRecords = report.records.filter(record => expectedIds.has(record.id));
  const selectedPassed = selectedRecords.filter(record => record.passed).length;
  report.selected_summary = { passed: selectedPassed, total: selected.length };
  saveReport(options.reportPath, report);
  process.stdout.write(`${JSON.stringify({ ...report.selected_summary, report: options.reportPath })}\n`);
  process.exitCode = selectedPassed === selected.length ? 0 : 1;
}

main().catch(error => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
