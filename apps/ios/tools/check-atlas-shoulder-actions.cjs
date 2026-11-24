// Original source/control/analytic pose audit only; no native Swift execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI"), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const source = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(app, "GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\bindex\b/g, "i").replace(/(^|[^\d])\.(\d)/g, "$10.$2").replace(/\s/g, "");
const originalCommands = body => [...body.matchAll(/(?:fan|scratch|path|p)\.(moveTo|lineTo|quadTo|cubicTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
const nativeCommands = body => [...body.matchAll(/p\.(move|addLine|addQuadCurve|addCurve|closeSubpath)\(([^\n]*)/g)].flatMap(m => {
  // Commands may share a line, so consume just this call's balanced parentheses.
  const text = body.slice(m.index + m[0].indexOf("(") + 1); let end = 0, depth = 1;
  for (; end < text.length && depth; end++) { if (text[end] === "(") depth++; if (text[end] === ")") depth--; }
  const points = [...text.slice(0, end - 1).matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(p => [norm(p[1]), norm(p[2])]);
  const result = [[{move: "moveTo", addLine: "lineTo", addQuadCurve: "quadTo", addCurve: "cubicTo", closeSubpath: "close"}[m[1]], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())]];
  const rest = m[0].slice(m[0].indexOf("(") + 1 + end);
  return result.concat(rest.includes("p.") ? nativeCommands(rest) : []);
});
let paths = 0, commands = 0, labels = 0;
const sources = {};
for (const [name, expected] of [["Pectoral", 5], ["Latissimus", 6]]) {
  const kotlin = sources[name] = source(name + "ActionStoryView"), geometry = local(name + "Geometry");
  const shapes = [...kotlin.matchAll(/private val (\w+) = Path\(\)\.apply \{([\s\S]*?)\n    \}/g)]; assert.equal(shapes.length, expected);
  for (const [, id, body] of shapes) {
    const actual = geometry.match(new RegExp("static let " + id + " = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
    // Static declarations omit a receiver on the original Path DSL commands.
    const original = originalCommands(body.replace(/\b(moveTo|lineTo|quadTo|cubicTo|close)\(/g, "p.$1("));
    assert.deepEqual(nativeCommands(actual), original, name + ":" + id); paths++; commands += original.length;
  }
  const drawing = local(name + "Drawing");
  for (const [, key, args] of kotlin.matchAll(/label\(c, R.string.health_atlas_(\w+), ([\d.f, ]+)\)/g)) {
    assert(norm(drawing).includes(norm('label("' + key + '", ' + args + ')')), key); labels++;
    for (const language of ["en", "zh-Hans"]) assert(fs.readFileSync(path.join(app, language + ".lproj/AtlasRegional.strings"), "utf8").includes('"health_atlas_' + key + '"'));
  }
}
for (const [name, method, file] of [["Pectoral", "drawPectoralFan", "PectoralFanDrawing"], ["Latissimus", "drawSheet", "LatissimusSheetDrawing"], ["Latissimus", "drawBack", "LatissimusBackDrawing"]]) {
  const body = sources[name].match(new RegExp("private fun " + method + "\\([^\\n]+\\) \\{([\\s\\S]*?)\\n    \\}"))[1];
  assert.deepEqual(nativeCommands(local(file)), originalCommands(body), file + " parameterized controls");
}
const motion = local("ShoulderActionMotion"), androidMotion = source("ShoulderActionMotion");
for (const [a, b] of [["START_ANGLE = -12f", "startAngle = -12.0"], ["SWEEP_ANGLE = 122f", "sweepAngle = 122.0"], [".48f * t", "0.48 * t"], [".48f + .52f * t", "0.48 + 0.52 * t"], ["1f - t", "1 - t"], ["FORWARD_ANGLE = 1.18f", "1.18 + (-0.12 - 1.18) * pose"], ["BACK_ANGLE = -.12f", "sin(-0.12)"], ["UPPER_LATERAL = .52f", "lateral = 0.52"], ["LOWER_LATERAL = .10f", "(0.10 - 0.52)"], ["sqrt(1f - lateral * lateral - anterior * anterior)", "sqrt(1 - lateral * lateral - anterior * anterior)"]]) { assert(androidMotion.includes(a), a); assert(motion.includes(b), b); }
for (const token of ["0.65 * lateral + 0.76 * anterior", "0.98 * down + 0.15 * lateral - 0.13 * anterior", "2 - ease(f * 2)", "1 - ease(f * 2 - 1)", "29 * cos(radians) - 8 * sin(radians)", "29 * sin(radians) + 8 * cos(radians)"]) assert(motion.includes(token));
for (const token of ["radius: 125", "clockwise: false", "returning ? start + sweep - angle : angle - start", "returning ? 4 : -4", "step >= 2", "local.rotate(by: .degrees(angle))"]) assert(local("PectoralDrawing").includes(token));
for (const token of ["dy / scale * 7", "dx / scale * 7", "local.rotate(by: .radians(atan2(dy, dx)))", "local.scaleBy(x: scale, y: 1)", "returning && pose < 1", "pose - 0.04", "pose + 0.04", "returning ? -1.0 : 1"]) assert(local("LatissimusDrawing").includes(token));
assert(local("LatissimusSheetDrawing").includes("dash: [3, 2.5]")); assert(local("LatissimusGeometry").includes("for i in 0...20"));
const ease = f => f * f * (3 - 2 * f);
const angle = (s, f) => -12 + 122 * (s === 2 ? 0.48 * ease(f) : s === 3 ? 0.48 + 0.52 * ease(f) : s === 4 ? 1 - ease(f) : 0);
const pose = (s, f) => s === 2 ? ease(f) : s === 3 ? 1 + ease(f) : s === 4 ? f < 0.5 ? 2 - ease(f * 2) : 1 - ease(f * 2 - 1) : 0;
const project = p => { const r = Math.sqrt(1 - 0.52 ** 2), l = p <= 1 ? 0.52 : 0.52 + (0.10 - 0.52) * (p - 1), a = p <= 1 ? r * Math.sin(1.18 + (-0.12 - 1.18) * p) : r * Math.sin(-0.12), d = p <= 1 ? r * Math.cos(1.18 + (-0.12 - 1.18) * p) : Math.sqrt(1 - l * l - a * a); return [0.65 * l + 0.76 * a, 0.98 * d + 0.15 * l - 0.13 * a]; };
assert.equal(angle(2, 1), angle(3, 0)); assert.equal(angle(3, 1), angle(4, 0)); assert.equal(angle(4, 1), -12);
assert.equal(pose(2, 1), pose(3, 0)); assert.equal(pose(3, 1), pose(4, 0)); assert.equal(pose(4, 1), 0); assert.equal(pose(4, 0.5), 1);
let samples = 0;
for (let step = 0; step < 5; step++) for (let tick = 0; tick <= 120; tick++) {
  const f = tick / 120, a = angle(step, f), p = pose(step, f), [dx, dy] = project(p), length = Math.hypot(dx, dy);
  assert(a >= -12 && a <= 110 && p >= 0 && p <= 2 && length > 0.001);
  const tx = 220 + dx * 25 + dy / length * 7, ty = 121 + dy * 25 - dx / length * 7;
  assert(Number.isFinite(tx) && Number.isFinite(ty) && tx >= 0 && tx <= 360 && ty >= 0 && ty <= 360); samples++;
}
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const file of ["ShoulderActionMotion", "PectoralGeometry", "PectoralDrawing", "PectoralFanDrawing", "PectoralView", "LatissimusGeometry", "LatissimusDrawing", "LatissimusBackDrawing", "LatissimusSheetDrawing", "LatissimusView"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlas" + file + ".swift;").length - 1, 1);
console.log("Android #4385 shoulders: " + paths + " exact outlines/" + commands + " static commands, original fan/sheet/back controls, " + labels + " bilingual labels and " + samples + " analytic two-course poses/phase continuity. Runtime activation pending; no native execution.");
