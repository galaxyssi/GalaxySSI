const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const checker = new vm.Script(fs.readFileSync(path.join(__dirname, "check.js"), "utf8"));
const packagerPath = path.join(__dirname, "package-win.js");

function checkWith(overrides = {}) {
  checker.runInNewContext({
    __dirname,
    console: { log() {} },
    require(name) {
      if (name === "node:fs") return { ...fs, ...overrides };
      if (name === "node:path") return path;
      throw new Error(`Unexpected checker dependency: ${name}`);
    }
  }, { timeout: 30000 });
}

test("the current packaged backend data satisfies the structure gate", () => {
  assert.doesNotThrow(() => checkWith());
});

for (const missing of ["web_source_sites.tsv", "research_contract"]) {
  test(`packaging cannot silently omit ${missing}`, () => {
    assert.throws(() => checkWith({
      readFileSync(file, ...args) {
        const content = fs.readFileSync(file, ...args);
        return path.resolve(file) === packagerPath
          ? content.replace('const backendDataEntries = ["web_source_sites.tsv", "research_contract"]',
            `const backendDataEntries = [${JSON.stringify(missing === "research_contract"
              ? "web_source_sites.tsv" : "research_contract")}]`)
          : content;
      }
    }), /Packaged Desktop backend auto-discovery is incomplete/);
  });
}

for (const relative of [
  "web_source_sites.tsv",
  "research_contract/research-quality.json",
  "research_contract/research-audit-tool.json",
  "research_contract/quality-cases.json"
]) {
  test(`the gate rejects missing backend data: ${relative}`, () => {
    const missing = path.join(root, "core", "galaxyssi-link", "backend", relative);
    assert.throws(() => checkWith({
      existsSync(file) { return path.resolve(file) !== missing && fs.existsSync(file); }
    }), /Missing core\/galaxyssi-link\/backend\//);
  });
}
