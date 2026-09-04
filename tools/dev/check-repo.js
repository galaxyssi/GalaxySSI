#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const rootPackageJson = path.join(root, "package.json");
const testingMatrix = path.join(root, "docs", "testing", "README.md");
const productRequirements = path.join(root, "docs", "product", "PRODUCT_REQUIREMENTS.md");
const readme = path.join(root, "README.md");
const trustModel = path.join(root, "docs", "security", "TRUST_MODEL.md");
const windowsPackageWorkflow = path.join(root, ".github", "workflows", "windows-package.yml");
const releaseAuditDoc = path.join(root, "docs", "testing", "RELEASE_AUDIT.md");
const releaseAuditScript = path.join(root, "tools", "dev", "release-audit.js");
const agentBenchmarkDoc = path.join(root, "docs", "testing", "AGENT_BENCHMARK.md");
const agentBenchmarkManifest = path.join(root, "benchmarks", "agent", "manifest.json");
const agentBenchmarkRunner = path.join(root, "tools", "benchmark", "run-agent-benchmark.mjs");
const agentRegressionSuite = path.join(root, "benchmarks", "agent", "regression-suite.json");
const agentRegressionRunner = path.join(root, "tools", "benchmark", "run-agent-regression.mjs");
const agentRegressionLibrary = path.join(root, "tools", "benchmark", "agent-regression-dsl.mjs");
const agentRegressionTest = path.join(root, "tools", "benchmark", "agent-regression-dsl.test.mjs");
const versionHealthDoc = path.join(root, "docs", "testing", "VERSION_HEALTH_SCORE.md");
const versionHealthPolicy = path.join(root, "benchmarks", "version-health", "policy.json");
const versionHealthEvidence = path.join(
  root,
  "benchmarks",
  "version-health",
  "reference-evidence.json"
);
const versionHealthRunner = path.join(root, "tools", "quality", "run-version-health-score.mjs");
const versionHealthLibrary = path.join(root, "tools", "quality", "version-health-score.mjs");
const versionHealthTest = path.join(root, "tools", "quality", "version-health-score.test.mjs");
const coreRegressionManifest = path.join(root, "tools", "dev", "core-regression-manifest.json");
const coreRegressionRunner = path.join(root, "tools", "dev", "run-core-regressions.mjs");
const memoryLoCoMoCorpus = path.join(root, "benchmarks", "memory", "locomo-corpus.json");
const trustedPrReviewWorkflow = path.join(root, ".github", "workflows", "trusted-pr-review.yml");
const trustedPrReviewPolicy = path.join(root, ".github", "trusted-pr-review-policy.json");
const trustedPrReviewDoc = path.join(root, "docs", "security", "TRUSTED_PR_REVIEW.md");
const trustedPrReviewChecker = path.join(root, "tools", "security", "check-trusted-pr-review.mjs");
const trustedPrReviewLibrary = path.join(root, "tools", "security", "trusted-pr-review-lib.mjs");
const trustedPrReviewTest = path.join(root, "tools", "security", "trusted-pr-review.test.mjs");

function listTrackedFiles() {
  const result = spawnSync("git", ["ls-files", "-z"], {
    cwd: root,
    encoding: "utf8",
    shell: false
  });

  if (result.error) {
    throw new Error(`Unable to list tracked files: ${result.error.message}`);
  }

  if (result.status !== 0) {
    throw new Error(`Unable to list tracked files: ${result.stderr || result.stdout}`);
  }

  return result.stdout.split("\0").filter(Boolean).map((file) => file.replace(/\\/g, "/"));
}

function checkNoTrackedGeneratedArtifacts() {
  const blocked = [
    { pattern: /^apps\/android\/galaxyssi-.*\.xml$/, reason: "Android UI dump" },
    { pattern: /^apps\/android\/.*\.(apk|aab|jks|keystore)$/i, reason: "Android package or signing artifact" },
    { pattern: /^apps\/desktop\/(dist|out|release|ui-smoke)\//, reason: "Desktop generated package or smoke artifact" },
    { pattern: /^apps\/desktop\/node_modules\//, reason: "Desktop dependency directory" },
    { pattern: /(^|\/)node_modules\//, reason: "Node dependency directory" },
    { pattern: /\.(exe|msi|dmg|AppImage|deb|rpm)$/i, reason: "packaged installer" },
    { pattern: /\.(db|sqlite|log|jsonl)$/i, reason: "local runtime data" },
    { pattern: /(^|\/)(galaxyssi_pairing_state\.json|galaxyssi_agents\.json|galaxyssi_push_token\.txt|galaxyssi_chat\.db)$/i, reason: "local identity or pairing state" },
    { pattern: /(^|\/)(uploads|downloads)\//, reason: "local file transfer data" }
  ];

  const offenders = [];
  for (const file of listTrackedFiles()) {
    const match = blocked.find((entry) => entry.pattern.test(file));
    if (match) {
      offenders.push(`${file} (${match.reason})`);
    }
  }

  if (offenders.length > 0) {
    throw new Error(`Generated or local artifacts are tracked:\n${offenders.join("\n")}`);
  }
}

function checkTestingMatrix() {
  if (!fs.existsSync(testingMatrix)) {
    throw new Error("Missing docs/testing/README.md");
  }

  const content = fs.readFileSync(testingMatrix, "utf8");
  const requiredText = [
    "Testing Matrix",
    "Required Gates",
    "Product Coverage",
    "Manual Release Checks",
    "npm run check",
    "npm run check:android",
    "npm run smoke:android:ui",
    "npm run smoke:android:friends",
    "npm run smoke:android:contact-rename",
    "npm run smoke:android:contact-tags",
    "npm run smoke:android:language",
    "npm run smoke:android:cloud-models",
    "npm run smoke:android:background",
    "npm run smoke:android:agent-replies",
    "npm run smoke:android:backup",
    "npm run smoke:android:voice-reply",
    "npm run smoke:android:voice-settings",
    "npm run smoke:android:reset",
    "npm run smoke:desktop",
    "npm run smoke:desktop:pairing",
    "npm run smoke:desktop:agent-push",
    "npm run smoke:desktop:voice-stt",
    "npm run smoke:desktop:mqtt-persistence",
    "npm run smoke:desktop:ui",
    "npm run smoke:desktop:e2e",
    "npm run smoke:desktop:voice-stt",
    "npm run package:desktop:win",
    "npm run smoke:desktop:packaged"
  ];

  for (const text of requiredText) {
    if (!content.includes(text)) {
      throw new Error(`Testing matrix missing: ${text}`);
    }
  }
}

function documentedNpmRunCommands(file) {
  const content = fs.readFileSync(file, "utf8");
  return [...content.matchAll(/npm run ([a-zA-Z0-9:._-]+)/g)]
    .map((match) => match[1].replace(/[.]+$/g, ""))
    .filter((scriptName, index, all) => all.indexOf(scriptName) === index)
    .sort();
}

function checkDocumentedRootScripts() {
  if (!fs.existsSync(rootPackageJson)) {
    throw new Error("Missing package.json");
  }

  const scripts = JSON.parse(fs.readFileSync(rootPackageJson, "utf8")).scripts || {};
  const docs = [
    testingMatrix,
    productRequirements,
    trustModel,
    releaseAuditDoc,
    releaseAuditScript,
    agentBenchmarkDoc,
    versionHealthDoc
  ];
  const missing = [];
  for (const file of docs) {
    for (const scriptName of documentedNpmRunCommands(file)) {
      if (!scripts[scriptName]) {
        missing.push(`${path.relative(root, file).replace(/\\/g, "/")}: npm run ${scriptName}`);
      }
    }
  }
  if (missing.length > 0) {
    throw new Error(`Documented npm scripts are missing from root package.json:\n${missing.join("\n")}`);
  }
}

function checkAgentBenchmark() {
  const packageJson = JSON.parse(fs.readFileSync(rootPackageJson, "utf8"));
  const requiredFiles = [
    agentBenchmarkDoc,
    agentBenchmarkManifest,
    agentBenchmarkRunner,
    agentRegressionSuite,
    agentRegressionRunner,
    agentRegressionLibrary,
    agentRegressionTest,
    path.join(root, "benchmarks", "agent", "reference-results.json"),
    path.join(root, "tools", "benchmark", "agent-benchmark-lib.mjs"),
    path.join(root, "tools", "benchmark", "agent-benchmark.test.mjs")
  ];
  for (const file of requiredFiles) {
    if (!fs.existsSync(file)) {
      throw new Error(`Missing Agent benchmark asset: ${path.relative(root, file)}`);
    }
  }
  for (const scriptName of [
    "benchmark:agent",
    "test:benchmark:agent",
    "regression:agent",
    "test:regression:agent"
  ]) {
    if (!packageJson.scripts?.[scriptName]) {
      throw new Error(`Missing Agent benchmark script: ${scriptName}`);
    }
  }
  const manifest = JSON.parse(fs.readFileSync(agentBenchmarkManifest, "utf8"));
  if (manifest.schema_version !== 1 || !Array.isArray(manifest.scenarios) || manifest.scenarios.length < 10) {
    throw new Error("Agent benchmark manifest must provide at least 10 schema v1 scenarios");
  }
  const regressionSuite = JSON.parse(fs.readFileSync(agentRegressionSuite, "utf8"));
  if (
    regressionSuite.dsl_version !== "galaxyssi.agent-regression.v1" ||
    !Array.isArray(regressionSuite.cases) ||
    regressionSuite.cases.length < 5
  ) {
    throw new Error(
      "Agent regression DSL must provide at least 5 galaxyssi.agent-regression.v1 cases"
    );
  }
}

function checkCoreRegressions() {
  const packageJson = JSON.parse(fs.readFileSync(rootPackageJson, "utf8"));
  for (const file of [
    coreRegressionManifest,
    coreRegressionRunner,
    path.join(root, "tools", "dev", "core-regressions.test.mjs")
  ]) {
    if (!fs.existsSync(file)) {
      throw new Error(`Missing core regression asset: ${path.relative(root, file)}`);
    }
  }
  for (const scriptName of ["test:core-regressions", "test:core-regressions:contract"]) {
    if (!packageJson.scripts?.[scriptName]) {
      throw new Error(`Missing core regression script: ${scriptName}`);
    }
  }
  const manifest = JSON.parse(fs.readFileSync(coreRegressionManifest, "utf8"));
  const identifiers = new Set((manifest.suites || []).map((suite) => suite.id));
  const required = [
    "android",
    "desktop",
    "mqtt",
    "memory",
    "remote_control",
    "agent_benchmark",
    "version_health"
  ];
  const missing = required.filter((identifier) => !identifiers.has(identifier));
  if (manifest.schema_version !== 1 || missing.length > 0) {
    throw new Error(`Core regression manifest is incomplete: ${missing.join(", ")}`);
  }
}

function checkVersionHealthScore() {
  const packageJson = JSON.parse(fs.readFileSync(rootPackageJson, "utf8"));
  for (const file of [
    versionHealthDoc,
    versionHealthPolicy,
    versionHealthEvidence,
    versionHealthRunner,
    versionHealthLibrary,
    versionHealthTest
  ]) {
    if (!fs.existsSync(file)) {
      throw new Error(`Missing version health asset: ${path.relative(root, file)}`);
    }
  }
  for (const scriptName of ["score:version-health", "test:version-health"]) {
    if (!packageJson.scripts?.[scriptName]) {
      throw new Error(`Missing version health script: ${scriptName}`);
    }
  }
  const policy = JSON.parse(fs.readFileSync(versionHealthPolicy, "utf8"));
  const requiredDimensions = [
    "performance",
    "reliability",
    "security",
    "ux",
    "memory_quality",
    "automation_success_rate"
  ];
  const dimensions = Array.isArray(policy.dimensions) ? policy.dimensions : [];
  const identifiers = new Set(dimensions.map((dimension) => dimension.id));
  const weight = dimensions.reduce(
    (total, dimension) => total + Number(dimension.weight || 0),
    0
  );
  if (
    policy.schema_version !== 1 ||
    requiredDimensions.some((identifier) => !identifiers.has(identifier)) ||
    Math.abs(weight - 1) > 0.000001
  ) {
    throw new Error("Version health policy must define all six normalized dimensions");
  }
  const evidence = JSON.parse(fs.readFileSync(versionHealthEvidence, "utf8"));
  if (
    evidence.schema_version !== 1 ||
    evidence.fixture !== true ||
    !Array.isArray(evidence.metrics) ||
    evidence.metrics.length < 12
  ) {
    throw new Error("Version health reference evidence must be an explicit deterministic fixture");
  }
}

function checkMemoryLoCoMoBenchmark() {
  const packageJson = JSON.parse(fs.readFileSync(rootPackageJson, "utf8"));
  const requiredFiles = [
    memoryLoCoMoCorpus,
    path.join(root, "docs", "testing", "MEMORY_LOCOMO_BENCHMARK.md"),
    path.join(root, "tools", "benchmark", "memory-locomo-lib.mjs"),
    path.join(root, "tools", "benchmark", "memory-locomo.test.mjs"),
    path.join(root, "tools", "benchmark", "run-memory-locomo.mjs"),
    path.join(
      root,
      "apps",
      "android",
      "app",
      "src",
      "test",
      "java",
      "com",
      "galaxyssi",
      "chat",
      "GlobalMemoryLoCoMoCorpusTest.kt"
    )
  ];
  for (const file of requiredFiles) {
    if (!fs.existsSync(file)) {
      throw new Error(`Missing memory LoCoMo benchmark asset: ${path.relative(root, file)}`);
    }
  }
  for (const scriptName of ["benchmark:memory-locomo", "test:benchmark:memory-locomo"]) {
    if (!packageJson.scripts?.[scriptName]) {
      throw new Error(`Missing memory LoCoMo benchmark script: ${scriptName}`);
    }
  }
  const corpus = JSON.parse(fs.readFileSync(memoryLoCoMoCorpus, "utf8"));
  const queryCount = (corpus.timelines || []).reduce(
    (total, timeline) => total + (timeline.queries || []).length,
    0
  );
  if (corpus.schema_version !== 1 || queryCount < 20) {
    throw new Error("Memory LoCoMo corpus must provide at least 20 schema v1 queries");
  }
}

function checkProductRequirements() {
  if (!fs.existsSync(productRequirements)) {
    throw new Error("Missing docs/product/PRODUCT_REQUIREMENTS.md");
  }

  const content = fs.readFileSync(productRequirements, "utf8");
  const requiredText = [
    "Product Requirements",
    "Product Principles",
    "Android Requirements",
    "Desktop Requirements",
    "Protocol And Security Requirements",
    "Release Requirements",
    "Deferred Scope",
    "Voice page",
    "Cloud models",
    "Language",
    "Destructive reset",
    "Agent contacts",
    "Pairing replacement",
    "npm run smoke:desktop:pairing",
    "docs/testing/README.md"
  ];

  for (const text of requiredText) {
    if (!content.includes(text)) {
      throw new Error(`Product requirements missing: ${text}`);
    }
  }
}

function checkReadme() {
  if (!fs.existsSync(readme)) {
    throw new Error("Missing README.md");
  }

  const content = fs.readFileSync(readme, "utf8");
  const requiredText = [
    "GalaxySSI",
    "Repository Layout",
    "npm run check",
    "npm run check:android",
    "npm run smoke:android:ui",
    "npm run smoke:android:friends",
    "npm run smoke:android:contact-rename",
    "npm run smoke:android:contact-tags",
    "npm run smoke:android:language",
    "npm run smoke:android:cloud-models",
    "npm run smoke:android:background",
    "npm run smoke:android:agent-replies",
    "npm run smoke:android:backup",
    "npm run smoke:android:voice-reply",
    "npm run smoke:android:voice-settings",
    "npm run smoke:android:reset",
    "npm run smoke:desktop",
    "npm run smoke:desktop:e2e",
    "npm run package:desktop:win",
    "npm run smoke:desktop:packaged",
    "npm run audit:release",
    "npm run audit:release:strict",
    "npm run test:release:local",
    "npm run test:release:device"
  ];

  for (const text of requiredText) {
    if (!content.includes(text)) {
      throw new Error(`README missing: ${text}`);
    }
  }
}

function checkTrustModel() {
  if (!fs.existsSync(trustModel)) {
    throw new Error("Missing docs/security/TRUST_MODEL.md");
  }

  const content = fs.readFileSync(trustModel, "utf8");
  const requiredText = [
    "Trust Model",
    "Trust Zones",
    "Identity And Pairing",
    "Message Protection",
    "Broker Boundary",
    "Local Data Boundary",
    "Agent Permission Boundary",
    "Current Security Limits",
    "Required Evidence",
    "/galaxyssi/verify",
    "opaque v2 pairing offer",
    "rotating directional mailboxes",
    "padded AES-GCM outer packet",
    "npm run smoke:android:reset",
    "npm run smoke:android:agent-replies",
    "npm run smoke:android:contact-rename",
    "npm run smoke:android:contact-tags",
    "npm run smoke:android:cloud-models",
    "npm run smoke:android:backup",
    "npm run smoke:android:voice-reply",
    "npm run smoke:android:voice-settings",
    "X-GalaxySSI-Token"
  ];

  for (const text of requiredText) {
    if (!content.includes(text)) {
      throw new Error(`Trust model missing: ${text}`);
    }
  }
}

function checkProtocolSpec() {
  const spec = path.join(root, "docs", "protocol", "GalaxySSI-Link-Protocol.md");
  if (!fs.existsSync(spec)) {
    throw new Error("Missing docs/protocol/GalaxySSI-Link-Protocol.md");
  }

  const content = fs.readFileSync(spec, "utf8");
  const requiredText = [
    "# GalaxySSI Link Protocol v2",
    "hard cut",
    "Public MQTT Surface",
    "[A-Za-z0-9_-]{43}",
    "One-Time Rendezvous",
    "Relationship Derivation",
    "AES-256-GCM",
    "six-hour epoch",
    "Encrypted Application Envelope",
    "Multiplexing",
    "Reliability and Fragmentation",
    "retain=false",
    "Revocation",
    "discarded rather than migrated",
    "There is no v1 compatibility path."
  ];

  for (const text of requiredText) {
    if (!content.includes(text)) {
      throw new Error(`Protocol spec missing: ${text}`);
    }
  }

  const androidProtocol = fs.readFileSync(
    path.join(root, "apps", "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "GalaxySSILinkProtocol.kt"),
    "utf8"
  );
  const desktopProtocol = fs.readFileSync(
    path.join(root, "apps", "desktop", "core", "galaxyssi-link", "backend", "link_protocol.py"),
    "utf8"
  );
  const androidChunking = fs.readFileSync(
    path.join(root, "apps", "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "GalaxySSIMqttWireChunking.kt"),
    "utf8"
  );
  const desktopChunking = fs.readFileSync(
    path.join(root, "apps", "desktop", "core", "galaxyssi-link", "backend", "mqtt_wire_chunking.py"),
    "utf8"
  );
  const alignedLimits = [
    [androidProtocol, "private const val MAX_OPAQUE_PACKET_BYTES = 1024 * 1024"],
    [androidProtocol, "const val MAX_ENVELOPE_BYTES = 512 * 1024"],
    [desktopProtocol, "MAX_OPAQUE_PACKET_BYTES = 1024 * 1024"],
    [desktopProtocol, "MAX_ENVELOPE_BYTES = 512 * 1024"],
    [androidChunking, "const val DEFAULT_DIRECT_LIMIT_BYTES = 512 * 1024 - 5"],
    [androidChunking, "const val DEFAULT_CHUNK_DATA_BYTES = 512 * 1024"],
    [androidChunking, "const val MAX_REASSEMBLED_BYTES = 2 * 1024 * 1024"],
    [androidChunking, "const val MAX_CHUNK_COUNT = 96"],
    [androidChunking, "const val MAX_PACKET_BYTES = 1024 * 1024"],
    [desktopChunking, "DIRECT_LIMIT_BYTES = 512 * 1024 - 5"],
    [desktopChunking, "CHUNK_DATA_BYTES = 512 * 1024"],
    [desktopChunking, "MAX_REASSEMBLED_BYTES = 2 * 1024 * 1024"],
    [desktopChunking, "MAX_CHUNK_COUNT = 96"],
    [desktopChunking, "MAX_PACKET_BYTES = 1024 * 1024"]
  ];

  for (const [source, expected] of alignedLimits) {
    if (!source.includes(expected)) {
      throw new Error(`GalaxySSI Link implementation limit drifted: ${expected}`);
    }
  }

  const compactAndroidProtocol = androidProtocol.replace(/\s+/g, "");
  const compactDesktopProtocol = desktopProtocol.replace(/\s+/g, "");
  const bucketSequence = "1024,16*1024,64*1024,128*1024,256*1024,512*1024";
  if (!compactAndroidProtocol.includes(`wireBuckets=intArrayOf(${bucketSequence})`)) {
    throw new Error("Android GalaxySSI Link padding buckets drifted from the protocol spec");
  }
  if (!compactDesktopProtocol.includes(`_WIRE_BUCKETS=(${bucketSequence},)`)) {
    throw new Error("Desktop GalaxySSI Link padding buckets drifted from the protocol spec");
  }

  const documentedLimits = [
    "buckets: 1 KiB, 16 KiB, 64 KiB, 128 KiB, 256 KiB, or 512 KiB",
    "A sealed packet MUST NOT exceed 1 MiB.",
    "`512 KiB - 5 bytes`",
    "128 KiB wire chunks",
    "180 KiB before outer encryption",
    "2 MiB after",
    "or 96 chunks"
  ];
  for (const expected of documentedLimits) {
    if (!content.includes(expected)) {
      throw new Error(`Protocol spec limit drifted: ${expected}`);
    }
  }
}

function checkWindowsPackageWorkflow() {
  if (!fs.existsSync(windowsPackageWorkflow)) {
    throw new Error("Missing .github/workflows/windows-package.yml");
  }

  const content = fs.readFileSync(windowsPackageWorkflow, "utf8");
  const requiredText = [
    "Windows Package",
    "runs-on: windows-latest",
    "pull_request:",
    "push:",
    "npm --prefix apps/desktop ci",
    "npm run package:desktop:win",
    "npm run smoke:desktop:packaged",
    "gradle/actions/setup-gradle"
  ];

  for (const text of requiredText) {
    if (!content.includes(text)) {
      throw new Error(`Windows package workflow missing: ${text}`);
    }
  }
}

function checkTrustedPrReviewPolicy() {
  const packageJson = JSON.parse(fs.readFileSync(rootPackageJson, "utf8"));
  const requiredFiles = [
    trustedPrReviewWorkflow,
    trustedPrReviewPolicy,
    trustedPrReviewDoc,
    trustedPrReviewChecker,
    trustedPrReviewLibrary,
    trustedPrReviewTest
  ];
  for (const file of requiredFiles) {
    if (!fs.existsSync(file)) {
      throw new Error(`Missing trusted PR review asset: ${path.relative(root, file)}`);
    }
  }
  if (!packageJson.scripts?.["test:trusted-pr-review"]) {
    throw new Error("Missing trusted PR review regression script");
  }

  const policy = JSON.parse(fs.readFileSync(trustedPrReviewPolicy, "utf8"));
  if (policy.schema !== "galaxyssi.trusted-pr-review.v1") {
    throw new Error("Trusted PR review policy schema is invalid");
  }
  if (!Array.isArray(policy.trusted_bot_logins) || policy.trusted_bot_logins.length === 0) {
    throw new Error("Trusted PR review policy must list at least one bot");
  }
  if (policy.trusted_bot_logins.some((login) => !String(login).endsWith("[bot]"))) {
    throw new Error("Trusted automated reviewers must use explicit GitHub bot identities");
  }
  const requiredChecks = new Set(policy.required_checks || []);
  for (const check of [
    "repository-check",
    "android-build",
    "desktop-source-smoke",
    "core-regressions",
    "package-win"
  ]) {
    if (!requiredChecks.has(check)) {
      throw new Error(`Trusted PR review policy is missing required CI check: ${check}`);
    }
  }

  const workflow = fs.readFileSync(trustedPrReviewWorkflow, "utf8");
  for (const text of [
    "pull_request_review:",
    "types: [submitted, edited]",
    "checks: read",
    "statuses: read",
    "pull-requests: write",
    "github.event.repository.default_branch",
    "persist-credentials: false",
    "node tools/security/check-trusted-pr-review.mjs"
  ]) {
    if (!workflow.includes(text)) {
      throw new Error(`Trusted PR review workflow missing: ${text}`);
    }
  }
  if (workflow.includes("pull_request_target:")) {
    throw new Error("Trusted PR review workflow must not execute through pull_request_target");
  }
}

function checkReleaseAudit() {
  if (!fs.existsSync(releaseAuditDoc)) {
    throw new Error("Missing docs/testing/RELEASE_AUDIT.md");
  }
  if (!fs.existsSync(releaseAuditScript)) {
    throw new Error("Missing tools/dev/release-audit.js");
  }

  const doc = fs.readFileSync(releaseAuditDoc, "utf8");
  const script = fs.readFileSync(releaseAuditScript, "utf8");
  const requiredText = [
    "npm run audit:release",
    "Repository Guard",
    "Windows Package",
    "Manual Release Checks",
    "npm run audit:release:strict",
    "npm run test:release:local",
    "npm run test:release:device",
    "smoke:desktop:mqtt-persistence",
    "smoke:desktop:voice-stt",
    "smoke:android:ui",
    "smoke:android:friends",
    "smoke:android:contact-rename",
    "smoke:android:contact-tags",
    "smoke:android:language",
    "smoke:android:cloud-models",
    "smoke:android:background",
    "smoke:android:agent-replies",
    "smoke:android:backup",
    "smoke:android:voice-reply",
    "smoke:android:voice-settings",
    "smoke:android:reset"
  ];

  for (const text of requiredText) {
    if (!doc.includes(text) && !script.includes(text)) {
      throw new Error(`Release audit missing: ${text}`);
    }
  }
}

const checks = [
  {
    name: "testing matrix",
    run: checkTestingMatrix
  },
  {
    name: "documented npm scripts",
    run: checkDocumentedRootScripts
  },
  {
    name: "Agent benchmark",
    run: checkAgentBenchmark
  },
  {
    name: "core regressions",
    run: checkCoreRegressions
  },
  {
    name: "Kotlin source size",
    command: process.execPath,
    args: [path.join(root, "tools", "quality", "check-kotlin-source-size.mjs")]
  },
  {
    name: "version health score",
    run: checkVersionHealthScore
  },
  {
    name: "memory LoCoMo benchmark",
    run: checkMemoryLoCoMoBenchmark
  },
  {
    name: "product requirements",
    run: checkProductRequirements
  },
  {
    name: "README",
    run: checkReadme
  },
  {
    name: "trust model",
    run: checkTrustModel
  },
  {
    name: "protocol spec",
    run: checkProtocolSpec
  },
  {
    name: "trusted PR review",
    run: checkTrustedPrReviewPolicy
  },
  {
    name: "windows package workflow",
    run: checkWindowsPackageWorkflow
  },
  {
    name: "release audit",
    run: checkReleaseAudit
  },
  {
    name: "tracked artifact policy",
    run: checkNoTrackedGeneratedArtifacts
  },
  {
    name: "i18n text policy",
    command: process.execPath,
    args: [path.join(root, "tools", "dev", "check-no-chinese-outside-i18n.js")]
  },
  {
    name: "desktop structure",
    command: process.execPath,
    args: [path.join(root, "apps", "desktop", "scripts", "check.js")]
  }
];

for (const check of checks) {
  console.log(`\n[check] ${check.name}`);
  if (check.run) {
    check.run();
    continue;
  }

  const result = spawnSync(check.command, check.args, {
    cwd: root,
    stdio: "inherit",
    shell: false
  });
  if (result.error) {
    console.error(`[check] ${check.name} failed to start: ${result.error.message}`);
    process.exit(1);
  }

  if (result.status !== 0) {
    console.error(`[check] ${check.name} failed`);
    process.exit(result.status || 1);
  }
}

console.log("\nGalaxySSI repository checks OK");
