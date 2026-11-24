// Pinned declaration/control/analytic model audit; not native renderer execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI"), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasUterocervicalStoryView.kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(app, "GalaxySSIHealthAtlasUterocervical" + name + ".swift"), "utf8");
cp.execFileSync(process.execPath, [path.join(__dirname, "import-atlas-uterocervical-geometry.cjs"), "--check"], {cwd: root, stdio: "inherit"});
const motion = local("Motion"), locator = local("LocatorDrawing"), detail = local("DetailDrawing"), vaginal = local("VaginalDrawing"), drawing = local("Drawing");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\bindex\b/g, "i").replace(/\s/g, "");
const commands = [...source.slice(source.indexOf("movingLining.moveTo(233f"), source.indexOf("surface(c, movingLining")).matchAll(/movingLining\.(moveTo|cubicTo|quadTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
const nativeCommands = [...vaginal.matchAll(/p\.(move|addCurve|addQuadCurve|closeSubpath)\(([^\n]*)/g)].flatMap(m => {
  const input = vaginal.slice(m.index + m[0].indexOf("(") + 1); let end = 0, depth = 1;
  for (; end < input.length && depth; end++) { if (input[end] === "(") depth++; if (input[end] === ")") depth--; }
  const points = [...input.slice(0, end - 1).matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(p => [norm(p[1]), norm(p[2])]);
  const result = [[{move: "moveTo", addCurve: "cubicTo", addQuadCurve: "quadTo", closeSubpath: "close"}[m[1]], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())]];
  // The only second operation sharing a line is the final closeSubpath.
  if (input.slice(end).split(/\r?\n/)[0].includes("p.closeSubpath()")) result.push(["close"]);
  return result;
});
assert.deepEqual(nativeCommands, commands, "moving fold surface controls");
assert(vaginal.includes("232 - 4.4 * index + 1.12 * index * index")); assert(vaginal.includes("108 + 22 * index")); assert(vaginal.includes("for i in 0...4"));
for (const token of ["- 0.08) / 0.84", "0.17 + 0.33 * Double(layer)", "/ 0.26", "1 - 0.53 * ease(1 - abs(2 *", "f * f * (3 - 2 * f)"]) assert(motion.includes(token));
let callouts = 0;
for (const [, key, args] of source.matchAll(/callout\(c, string.health_atlas_uterocervical_(\w+), ([^\n]+)\)/g)) {
  assert(norm(detail + vaginal).includes(norm('uterocervicalCallout("' + key + '", ' + args + ')')), key); callouts++;
}
assert.equal(callouts, 9);
for (const token of ["g.tracks[step]", 'let owners = ["uterus", "cervix", "vagina"]', "line(100, 269, 108, 269, 0xFFF5E7, 2.3)", "step == 0 ? g.locatorUterus : step == 1 ? g.locatorCervix : g.locatorVagina"]) assert(locator.includes(token));
for (const token of ["local.clip(to: g.wallMuscle)", "Double(Int(180 * emphasis)) / 255", "1.2 + 4 * emphasis", "line(245, 253, 252, 253, 0xFFF5E7, 2.6)", "uterocervicalTrace(g.track"]) assert(detail.includes(token));
assert(drawing.includes("stroke(track.path.trimmedPath(from: 0, to: progress), 0x24776D, 2.15)")); assert(drawing.includes("disc(x, y, 2.9, 0x24776D, border: 0xFFF5E7)"));
const ease = value => { const f = Math.min(1, Math.max(0, value)); return f * f * (3 - 2 * f); };
let poses = 0;
for (let tick = 0; tick <= 120; tick++) {
  const t = tick / 120, sweep = ease((t - 0.08) / 0.84), depth = 1 - 0.53 * ease(1 - Math.abs(2 * t - 1));
  assert(sweep >= 0 && sweep <= 1 && depth >= 0.47 && depth <= 1);
  for (let layer = 0; layer < 3; layer++) { const focus = ease(1 - Math.abs(t - (0.17 + 0.33 * layer)) / 0.26); assert(focus >= 0 && focus <= 1); }
  poses++;
}
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const name of ["LocatorGeometry", "WallGeometry", "CanalGeometry", "VaginalGeometry", "Motion", "Drawing", "LocatorDrawing", "DetailDrawing", "VaginalDrawing", "View"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlasUterocervical" + name + ".swift;").length - 1, 1);
console.log("Android #4385 uterocervical: 29 Kotlin-evaluated static paths/216 commands, original dynamic lining controls, nine callouts, fixed locator/openings and " + poses + " analytic motion samples. Runtime activation pending; no native execution.");
