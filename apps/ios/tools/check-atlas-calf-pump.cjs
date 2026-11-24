// Pinned source/formula/resource audit only; not Swift, XCTest, or native rendering execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const local = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const android = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
const source = android("Physiology"), native = local("Physiology"), art = local("MaterialResponseDrawing"), view = local("MaterialResponseView");
const text = local("PhysiologyText"), norm = s => s.replace(/\s+/g, "");
for (const [key, low, high, initial, unit] of [["stroke", 0, 25, 12, "mL"], ["rate", 0, 30, 12, "/min"], ["return", 0, 100, 0, "%"]]) {
  assert(source.includes('HealthAtlasInput("calf-' + key + '", ' + low + '..' + high + ', ' + initial + ')'));
  assert(native.includes('key: "calf_pump_' + key + '", range: ' + low + '...' + high + ', initial: ' + initial + ', unit: "' + unit + '"'));
}
assert(norm(source).includes("values[1]*netStroke(values[0],values[2])"));
assert(norm(native).includes("values[1]*Self.netStroke(ejected:values[0],returnPercent:values[2])"));
assert(norm(source).includes("ejected*(100.0-returnPercent)/100.0"));
assert(norm(native).includes("ejected*(100-returnPercent)/100"));
assert(native.includes("case .calfPump: return Self.netStroke(ejected: input(0), returnPercent: input(2))"));
assert(native.indexOf("if self == .calfPump { return 1 }") < native.indexOf("if hasMaterialResponse { return 0 }"));
for (const value of ['"soleus", "gastrocnemius": return .calfPump', 'if self == .calfPump { return 0...750 }', 'if self == .calfPump { return "mL/min" }']) assert(native.includes(value));
for (const id of ["24415543", "8445740"]) { assert(source.includes("https://pubmed.ncbi.nlm.nih.gov/" + id + "/")); assert(native.includes("https://pubmed.ncbi.nlm.nih.gov/" + id + "/")); }
const androidArt = android("MaterialResponseView"), start = androidArt.indexOf("private fun drawCalfPump"), end = androidArt.indexOf("private fun rectangle", start);
const originalArt = androidArt.slice(start, end), geometry = art.slice(art.indexOf("func calfPump"), art.indexOf("func exchange"));
// Compare all fixed chamber, valve and guide segment coordinates/colors/widths.
for (const match of originalArt.matchAll(/(?:rectangle|line)\(c, ([^\n]+)\)/g)) {
  const converted = match[1].replace(/(\d+)f\b/g, "$1").replace(/\b(rose|teal)\b/g, "Self.$1").replace(/0xff([0-9a-f]+)\.toInt\(\)/gi, (_, hex) => "0x" + hex.toUpperCase());
  const name = match[0].startsWith("line") ? "line" : "rectangle";
  const expected = name === "rectangle" && /, (18|14)$/.test(converted) ? converted.replace(/, (18|14)$/, ", radius: $1") : converted;
  if (!expected.includes("top")) assert(norm(geometry).includes(norm(name + "(" + expected + ")")), expected);
}
for (const value of ["115 - 71 * stroke / 25", "min((113 - top) * 0.45, 12)", "196 + max(6, 118 * total / 750)", "314 - max(6, 118 * returning / 750)", "if total > 0", "if returning > 0"]) assert(geometry.includes(value));
assert(art.includes("x2 >= x1 ? 1 : -1")); assert(art.includes("x2 - 6 * direction"));
assert(view.includes('"atlas-calf-pump"')); assert(view.includes('case .calfPump: art.calfPump(model)'));
assert(text.includes('"model_calfPump_formula": "calf_pump_formula"')); assert(text.includes('string("calf_pump_net_stroke"'));
for (const language of ["en", "zh-Hans"]) {
  const strings = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", language + ".lproj/AtlasRegional.strings"), "utf8");
  for (const key of ["title", "stroke", "rate", "return", "net_stroke", "formula", "scope", "diagram", "chamber_label", "forward_label", "return_label"]) assert(strings.includes('"health_atlas_calf_pump_' + key + '"'), language + ":" + key);
}
let cases = 0;
for (let stroke = 0; stroke <= 25; stroke++) for (let rate = 0; rate <= 30; rate++) for (let returning = 0; returning <= 100; returning++) {
  const net = stroke * (100 - returning) / 100, flow = rate * net;
  assert(Number.isFinite(flow) && flow >= 0 && flow <= 750);
  if (!stroke || !rate || returning === 100) assert.equal(flow, 0);
  if (!returning) assert.equal(flow, stroke * rate);
  cases++;
}
const ligament = local("LigamentDrawing");
assert(ligament.includes("step == 0 ? phase")); assert(ligament.includes("step == 0 ? 1 - phase"));
console.log("Android #4385 calf pump: source-linked inputs/formula/axis, bilingual text, chamber/valve/flow geometry and " + cases + " analytic grid combinations. Ligament first-chapter focus synchronized. No Swift/native execution.");
