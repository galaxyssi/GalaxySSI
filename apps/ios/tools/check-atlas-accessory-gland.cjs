// Pinned source/control/annotation checks; not Swift or native renderer execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI");
const source = cp.execFileSync("git", ["show", "a81aa85a1c81e41ff19a032eabea1eddcd2371dc:apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAccessoryGlandRoutingStoryView.kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(app, "GalaxySSIHealthAtlasAccessoryGland" + name + ".swift"), "utf8");
const routes = local("Routes"), labels = local("Labels"), drawing = local("Drawing");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "");
const paths = [...source.matchAll(/private val (\w+) = route\(([^)]+)\) \{([\s\S]*?)\n    \}/g)]; assert.equal(paths.length, 6);
const inks = new Map([...source.matchAll(/private val (\w+) = 0xff([0-9a-f]+)/g)].map(m => [m[1], parseInt(m[2], 16)]));
const colors = [...routes.match(/static let colors: \[UInt32\] = \[([^\]]+)\]/)[1].matchAll(/0x([0-9A-F]+)/g)].map(m => parseInt(m[1], 16));
assert.deepEqual(colors, paths.map(p => p[2].startsWith("0xff") ? parseInt(p[2].slice(4), 16) : inks.get(p[2])));
for (const [, name, , body] of paths) {
  const expected = [...body.matchAll(/(?:moveTo|cubicTo|quadTo)\(([^)]*)\)/g)].flatMap(m => m[1].split(",").map(norm));
  const native = routes.match(new RegExp("static let " + name + " = GalaxySSIHealthAtlasRegionalTrack\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  assert.deepEqual([...native.matchAll(/[xy]: ([^,)]+)/g)].map(m => norm(m[1])), expected, name);
}
// Evaluate the restricted literal Callout declarations and copy overrides; reject unknown expressions.
function split(text) {
  const result = []; let depth = 0, start = 0;
  for (let i = 0; i < text.length; i++) { if (text[i] === "(") depth++; if (text[i] === ")") depth--; if (text[i] === "," && depth === 0) { result.push(text.slice(start, i).trim()); start = i + 1; } }
  if (text.slice(start).trim()) result.push(text.slice(start).trim()); return result;
}
function scalar(value) { value = value.trim().replace(/(\d)f\b/g, "$1"); if (value === "true") return true; if (value === "false") return false; assert(/^-?\d+(?:\.\d+)?$/.test(value)); return Number(value); }
function call(expression, base, android) {
  if (expression.startsWith("Callout(")) {
    const args = split(expression.slice(8, -1)); assert.equal(args.length, 5);
    const key = android ? args[0].replace(/^string.health_atlas_accessory_gland_routing_/, "") : JSON.parse(args[0]);
    return [key, ...args.slice(1).map(scalar)];
  }
  const match = expression.match(/^(\w+)(?:\.copy\((.*)\))?$/); assert(match, expression); assert(base.has(match[1]), expression);
  const result = [...base.get(match[1])];
  if (match[2]) for (const override of split(match[2])) { const [key, value] = override.split("=").map(s => s.trim()); const index = ["key", "x", "y", "row", "left"].indexOf(key); assert(index > 0); result[index] = scalar(value); }
  return result;
}
const originalBase = new Map([...source.matchAll(/private val (\w+) = (Callout\([^\n]+\))/g)].map(m => [m[1], call(m[2], new Map(), true)]));
const nativeBase = new Map([...labels.matchAll(/static let (\w+) = (Callout\([^\n]+\))/g)].map(m => [m[1], call(m[2], new Map(), false)]));
let callouts = 0;
for (const [step, name] of [[0, "locatorLabels"], [1, "vesicleLabels"], [2, "ejaculatoryLabels"], [3, "prostateLabels"], [4, "bulbLabels"]]) {
  const start = source.indexOf("private val " + name + " = listOf(") + ("private val " + name + " = listOf(").length;
  assert(start > 40); let end = start, depth = 1;
  for (; end < source.length && depth; end++) { if (source[end] === "(") depth++; if (source[end] === ")") depth--; }
  const expected = split(source.slice(start, end - 1)).map(expr => call(expr, originalBase, true));
  const branch = labels.match(new RegExp((step ? "case " + step : "default") + ": return \\[([^\\n]+)\\]"))[1];
  const actual = split(branch).map(expr => call(expr, nativeBase, false)); assert.deepEqual(actual, expected, name); callouts += actual.length;
}
for (const token of ["case 1: return index == 1", "case 2: return index == 2", "case 3: return index == 3 || index == 4", "case 4: return index == 5", "default: return index != 0", "(t - 0.04 - delay) / (0.84 - delay)", "p * p * (3 - 2 * p)"]) assert(routes.includes(token), token);
for (const token of ["local.translateBy(x: 0, y: 40)", 'Image("HealthAtlasRegionalAccessoryGlandRoutingCutaway")', "pairArt.stroke(track.path, color, active ? 4 : 3)", "pairArt.stroke(track.path, 0xF9ECDD, 1.5)", "delay: 0.17", "max(0, p - 0.22)", "for side in 0..<2", "local.scaleBy(x: -1, y: 1)", "callout.left ? 107.0 : 246", "callout.left ? 64 : 293"]) assert(drawing.includes(token), token);
let samples = 0;
for (const delay of [0, 0.17]) for (let tick = 0; tick <= 120; tick++) { const t = tick / 120, p = Math.min(1, Math.max(0, (t - 0.04 - delay) / (0.84 - delay))), progress = p * p * (3 - 2 * p); assert(progress >= 0 && progress <= 1); if (t <= 0.04 + delay) assert.equal(progress, 0); samples++; }
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const file of ["Routes", "Labels", "Drawing", "View"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlasAccessoryGland" + file + ".swift;").length - 1, 1);
console.log("Android #4385 accessory glands: six original bilateral route controls, " + callouts + " source-evaluated stage callouts, five routing/highlight contracts and " + samples + " analytic delay samples. Runtime activation pending; no native execution.");
