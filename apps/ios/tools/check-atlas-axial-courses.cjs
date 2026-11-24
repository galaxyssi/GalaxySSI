// Source and analytic geometry checks, not Swift execution or native pixel acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const {svgPathToOperators} = require("pdf-lib/cjs/api/svgPath.js");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const local = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const android = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
cp.execFileSync(process.execPath, [path.join(__dirname, "import-atlas-axial-geometry.cjs"), "--check"], {cwd: root, stdio: "inherit"});
const operators = data => svgPathToOperators(data).map(op => [op.name, ...op.args.map(n => n.asNumber())]);
assert.deepEqual(operators("M88 149 Q76 165 96 170 T115 195"), [["m", 88, 149], ["v", 76, 165, 96, 170], ["v", 116, 175, 115, 195]]);
assert.deepEqual(operators("M91 140 l8 -4 6 1 6 -5"), [["m", 91, 140], ["l", 99, 136], ["l", 105, 137], ["l", 111, 132]]);
const skull = local("SkullDrawing"), vertebral = local("VertebralDrawing"), motion = local("VertebralMotion");
const skullSource = android("SkullProtectionStoryView"), vertebralSource = android("VertebralMotionStoryView");
for (const token of ["step < 2", "locate: step == 0", "membranes: step == 3", "[g.coronal, g.sagittal, g.lambdoid]", "progress - Double(i)", "path.trimmedPath(from: 0, to: fraction)", "165 + t * 35", "dash: [4, 4]", "latticeContext.clip(to: g.diploe)", "fluidContext.clip(to: g.fluid)", "outsideBrain.addPath(g.brain)", "FillStyle(eoFill: true)", "t * 0.48 + Double(i) * 0.2", "for i in 0...4", "0xBB398295"]) assert(skull.includes(token), token);
const norm = text => text.replace(/(\d)f\b/g, "$1").replace(/\s/g, "");
let callouts = 0;
for (const [, key, args] of skullSource.matchAll(/callout\(c, R.string.health_atlas_skull_protection_art_(\w+), ([^\n]+)\)/g)) {
  assert(norm(skull).includes(norm('skullCallout("' + key + '", ' + args + ')')), key); callouts++;
}
assert.equal(callouts, 12);
for (const [original, native] of [["t * t * (3f - 2f * t)", "t * t * (3 - 2 * t)"], ["-6.5f * bend else -3f * bend", "-6.5 * bend : -3 * bend"], ["-4f * bend else -2.2f * bend", "-4 * bend : -2.2 * bend"]]) { assert(vertebralSource.includes(original)); assert(motion.includes(native)); }
for (const token of ["step == 1 ? eased : step == 2 ? 1 - 2 * eased : 0", "angle * .pi / 180", "x - 119", "y - 151", "cos(radians) * dx - sin(radians) * dy + glide", "sin(radians) * dx + cos(radians) * dy", "point(73, 139)", "point(166, 139)", "point(232, 152)"]) assert(motion.includes(token), token);
for (const token of ["upper.translateBy(x: 119 + motion.glide, y: 151)", "upper.rotate(by: .degrees(motion.angle))", "upper.translateBy(x: -119, y: -151)", "lower.translateBy(x: 0, y: 108)", "min(2, Int(t * 3))", "dash: [3, 4]", "motion.bend > 0.12", "motion.bend < -0.12", "max(rx, 163) + 6", "min(lx, 73) - 6", "local.clip(to: outline)", "(ly + ry + 165 * 2) / 4", "for i in 1...3", "Double(i) / 4", "ly + (171 - ly) * f", "ry + (170 - ry) * f"]) assert(vertebral.includes(token), token);
// Analytic samples verify the ported rigid transform and noncollapsed disc attachments.
let poses = 0;
for (let step = 0; step < 3; step++) for (let tick = 0; tick <= 120; tick++) {
  const t = tick / 120, eased = t * t * (3 - 2 * t), bend = step === 1 ? eased : step === 2 ? 1 - 2 * eased : 0;
  const angle = (bend >= 0 ? -6.5 * bend : -3 * bend) * Math.PI / 180, glide = bend >= 0 ? -4 * bend : -2.2 * bend;
  const map = (x, y) => [119 + Math.cos(angle) * (x - 119) - Math.sin(angle) * (y - 151) + glide, 151 + Math.sin(angle) * (x - 119) + Math.cos(angle) * (y - 151)];
  const l = map(73, 139), r = map(166, 139);
  assert(Math.abs(Math.hypot(r[0] - l[0], r[1] - l[1]) - 93) < 1e-10);
  assert(l[1] < 171 && r[1] < 170 && l[0] < r[0]);
  if (!bend) { assert.deepEqual(l, [73, 139]); assert.deepEqual(r, [166, 139]); }
  poses++;
}
const catalogue = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasRegionalStories.dataset/content.json")));
for (const [id, chapters, native] of [["SKULL_PROTECTION", 4, "Skull"], ["VERTEBRAL_MOTION", 3, "Vertebral"]]) {
  const story = catalogue.stories.find(s => s.id === id); assert.equal(story.chapters.length, chapters);
  assert(local(native + "View").includes("story.fraction(phase)"));
}
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const name of ["SkullGeometry", "SkullDrawing", "SkullView", "VertebralGeometry", "VertebralMotion", "VertebralDrawing", "VertebralView"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlas" + name + ".swift;").length - 1, 1);
console.log("Android #4385 axial courses: exact 27-path regeneration, SVG relative/reflection fixtures, 12 skull callouts, clipped fluid tracers and " + poses + " analytic moving-disc poses. Runtime catalogue activation pending; no native execution.");
