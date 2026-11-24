// Source/vector conversion checks only; not native pixels or iOS rendering.
const assert = require("node:assert/strict"), cp = require("node:child_process"), path = require("node:path"), fs = require("node:fs");
const {svgPathToOperators} = require("pdf-lib/cjs/api/svgPath.js");
const normalize = require("./body-atlas-quadratic-path.cjs"), ordered = require("./body-atlas-ordered-vector.cjs");
const root = path.resolve(__dirname, "../../..");
const ops = data => svgPathToOperators(data).map(op => [op.name, ...op.args.map(n => n.asNumber())]);
assert.deepEqual(ops(normalize("M0 0 Q30 30 60 0 T120 0")), [["m", 0, 0], ["c", 20, 20, 40, 20, 60, 0], ["c", 80, -20, 100, -20, 120, 0]]);
assert.deepEqual(ops(normalize("M10 20 q30 60 90 0 Z m5 5 l10 0")), [["m", 10, 20], ["c", 30, 60, 60, 60, 100, 20], ["h"], ["m", 15, 25], ["l", 25, 25]]);
let samples = 0;
for (const [start, control, end] of [[[0, 0], [30, 30], [60, 0]], [[32, 119], [180, 37], [328, 119]], [[88, 149], [76, 165], [96, 170]]]) {
  const data = "M" + start.join(" ") + " Q" + [...control, ...end].join(" ");
  const cubic = ops(normalize(data))[1].slice(1), c1 = cubic.slice(0, 2), c2 = cubic.slice(2, 4);
  for (let tick = 0; tick <= 120; tick++) {
    const t = tick / 120, u = 1 - t;
    for (let axis = 0; axis < 2; axis++) {
      const q = u * u * start[axis] + 2 * u * t * control[axis] + t * t * end[axis];
      const c = u ** 3 * start[axis] + 3 * u * u * t * c1[axis] + 3 * u * t * t * c2[axis] + t ** 3 * end[axis];
      assert(Math.abs(q - c) < 1e-10);
    }
    samples++;
  }
}
const xml = '<vector xmlns:android="http://schemas.android.com/apk/res/android"><path android:pathData="M0 0 L1 1"/><group><clip-path android:pathData="M0 0 L2 0 L2 2 Z"/><path android:pathData="M1 1 L2 2"/><group><path android:pathData="M1 1 L3 3"/></group></group><path android:pathData="M3 3 L4 4"/></vector>';
const paths = ordered(xml, {affine: true, clips: true});
assert.equal(paths.length, 4); assert(!paths[0]._atlasClips); assert.equal(paths[1]._atlasClips.length, 1); assert.equal(paths[2]._atlasClips.length, 1); assert(!paths[3]._atlasClips);
assert.throws(() => ordered(xml, {affine: true}), /Unsupported atlas vector element clip-path/);
assert.throws(() => ordered(xml.replace("<group>", '<group android:translateX="1">'), {affine: true, clips: true}), /Transformed atlas clip/);
process.argv.push("--regional-4385");
const batch = require("./body-atlas-function-artwork.cjs");
assert.equal(batch.frames.length, 23); assert.equal(batch.paths, 298); assert.equal(batch.gradients, 68);
assert.equal(new Set(batch.frames.map(f => f[1])).size, 23);
for (const [, asset] of batch.frames) {
  const dir = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets", asset + ".imageset");
  assert(fs.statSync(path.join(dir, "art.pdf")).size > 0);
}
cp.execFileSync(process.execPath, [path.join(__dirname, "check-body-atlas-sensory-sections.cjs"), "--regional-4385"], {cwd: root, stdio: "inherit"});
console.log("Regional vectors: 23 source assets, nested clip scope/rejection, relative/reflected quadratic fixtures and " + samples + " exact-equivalence samples. No native rendering acceptance.");
