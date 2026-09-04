const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const hanPattern = /[\u3400-\u9fff]/;
const linguisticDataPolicyPath = path.join(__dirname, "i18n-linguistic-data.json");
const linguisticDataPolicy = JSON.parse(fs.readFileSync(linguisticDataPolicyPath, "utf8"));
if (linguisticDataPolicy.schema !== "galaxyssi.i18n-linguistic-data.v1") {
  throw new Error("Invalid i18n linguistic-data policy schema");
}
const linguisticDataFiles = new Set();
for (const entry of linguisticDataPolicy.files || []) {
  const relativePath = String(entry.path || "").replace(/\\/g, "/");
  if (!relativePath || !entry.reason || linguisticDataFiles.has(relativePath)) {
    throw new Error(`Invalid i18n linguistic-data policy entry: ${JSON.stringify(entry)}`);
  }
  linguisticDataFiles.add(relativePath);
}

function readSubmodulePaths() {
  const config = path.join(root, ".gitmodules");
  if (!fs.existsSync(config)) return new Set();
  const paths = fs
    .readFileSync(config, "utf8")
    .split(/\r?\n/)
    .map((line) => /^\s*path\s*=\s*(.+?)\s*$/.exec(line)?.[1])
    .filter(Boolean)
    .map((value) => value.replace(/\\/g, "/").replace(/\/$/, ""));
  return new Set(paths);
}

const ignoredSubmodulePaths = readSubmodulePaths();

const ignoredDirs = new Set([
  ".git",
  ".gradle",
  ".gradle-dist",
  ".cxx",
  ".kotlin",
  "build",
  "dist",
  "node_modules",
  "out",
  "release",
  "ui-smoke",
  "__pycache__",
  "venv",
  ".venv",
  "artifacts"
]);

const ignoredExtensions = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".webp",
  ".ico",
  ".apk",
  ".aab",
  ".aar",
  ".jar",
  ".onnx",
  ".tflite",
  ".bin",
  ".db",
  ".sqlite"
]);

function normalize(value) {
  return value.split(path.sep).join("/");
}

function isTestLanguageCorpus(rel) {
  return (
    /\/src\/(?:test|androidTest)\//.test(rel) ||
    /^apps\/desktop\/core\/galaxyssi-link\/backend\/(?:tests\/|test_[^/]+\.py$)/.test(rel) ||
    /^apps\/desktop\/scripts\/(?:smoke-[^/]+\.js|[^/]+\.test\.js|[^/]+-cases\.js)$/.test(rel) ||
    /^tools\/benchmark\//.test(rel)
  );
}

function isAllowedChineseFile(file) {
  const rel = normalize(path.relative(root, file));
  return (
    /^apps\/android\/app\/src\/main\/res\/values-zh-rCN\/[^/]+\.xml$/.test(rel) ||
    /^apps\/android\/app\/src\/main\/res\/values-b\+zh\+Hans\+CN\/[^/]+\.xml$/.test(rel) ||
    rel === "apps/desktop/src/renderer/locales/zh-CN.json" ||
    /apps\/ios\/.*\/zh-Hans\.lproj\/Localizable\.strings$/.test(rel) ||
    isTestLanguageCorpus(rel) ||
    linguisticDataFiles.has(rel)
  );
}

function walk(dir, findings) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const rel = normalize(path.relative(root, full));
      if (!ignoredDirs.has(entry.name) && !ignoredSubmodulePaths.has(rel)) walk(full, findings);
      continue;
    }
    if (entry.isSymbolicLink()) continue;
    if (ignoredExtensions.has(path.extname(entry.name).toLowerCase())) continue;
    if (isAllowedChineseFile(full)) continue;
    const text = fs.readFileSync(full, "utf8");
    if (!hanPattern.test(text)) continue;
    const lines = text.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (hanPattern.test(line)) {
        findings.push(`${normalize(path.relative(root, full))}:${index + 1}`);
      }
    });
  }
}

for (const relativePath of linguisticDataFiles) {
  const absolutePath = path.join(root, relativePath);
  if (!fs.existsSync(absolutePath)) {
    throw new Error(`Missing approved linguistic-data file: ${relativePath}`);
  }
  if (!hanPattern.test(fs.readFileSync(absolutePath, "utf8"))) {
    throw new Error(`Stale linguistic-data approval without Han text: ${relativePath}`);
  }
}

const findings = [];
walk(root, findings);

if (findings.length) {
  console.error("Chinese text is only allowed in i18n resource files:");
  for (const finding of findings) console.error(`  ${finding}`);
  process.exit(1);
}

console.log("Chinese text guard OK");
