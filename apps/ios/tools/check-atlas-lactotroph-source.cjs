// Source and analytic checks only; no native/Android lesson runs.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasLactotrophStoryView.kt"], {cwd: root, encoding: "utf8"});
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const drawing = read("LactotrophDrawing"), geometry = read("LactotrophGeometry");
assert.ok(source.includes("addCircle(170f, 171f, 47f, Path.Direction.CW)"));
assert.ok(geometry.includes("p.addEllipse(in: CGRect(x: 123, y: 124, width: 94, height: 94))"));
const ducts = geometry.slice(geometry.indexOf("static let ducts"), geometry.indexOf("static let lumenClip"));
assert.equal((ducts.match(/p\.move\(to:/g) || []).length, 5);
for (const token of ["local.clip(to: G.lumenClip)", "(0..<16).map", "(i + 1) % 16", "(i * 2 + 9) % 16",
  "(t - 0.09 - Double(i) * 0.035) / 0.43", "255 * (1 - relief)", "(t - 0.41 - Double(i) * 0.085) / 0.46",
  "p < 0.57", "t * 1.6 - Double(i) * 0.16", "(t - 0.57) / 0.3", "(t - 0.33 - 0.09 * Double(i)) / 0.32",
  "(approach - 0.68) * 2.5", "(t - 0.30) / 0.59", "(t - 0.11 - 0.093 * Double(i)) / 0.38", "50 - 37 * Self.pituitarySmooth(f)"]) assert.ok(drawing.includes(token), token);
for (const route of ["releaseBlood", "mammaryBlood", "nearAlveolus"]) assert.ok(geometry.includes("static let " + route + "Route ="));
const keys = [...new Set([...source.matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
const smooth = t => { const p = Math.max(0, Math.min(1, t)); return p * p * (3 - 2 * p); };
let active = 0, hidden = 0, droplets = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120, pool = smooth((t - .3) / .59), surface = 218 - 26 * pool;
  assert.ok(surface >= 192 && surface <= 218);
  for (let i = 0; i <= 5; i++) {
    const transport = t * 1.6 - i * .16;
    if (transport >= 0 && transport <= 1) active++; else hidden++;
    const f = (t - .11 - .093 * i) / .38;
    if (f >= 0 && f <= 1) {
      const k = (i * 2 + 9) % 16, r = 50 - 37 * smooth(f);
      const x = 170 + Math.cos(k * Math.PI / 8) * r, y = 171 + Math.sin(k * Math.PI / 8) * r;
      assert.ok(Math.abs(Math.hypot(x - 170, y - 171) - r) < 1e-10 && r >= 13 && r <= 50); droplets++;
    }
  }
}
assert.ok(active > 0 && hidden > 0 && droplets > 0);
console.log("Source-only lactotroph audit: five disconnected ducts, exact lumen clip, three transport routes, 16 epithelial directions, " + keys.length + " bilingual keys; " + droplets + " analytic droplets. No native/pixel acceptance.");
