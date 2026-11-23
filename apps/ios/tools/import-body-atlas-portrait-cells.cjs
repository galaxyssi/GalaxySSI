// Copy the current Android portrait plates without resampling and retire generated PDFs.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, "../../.."), assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
for (const [slug, asset] of [["cochlear_hair", "CochlearHair"], ["rod", "Rod"], ["cone", "Cone"]]) {
  const png = cp.execFileSync("git", ["show", "ac7ab99df542b67a7a0ea6a28999a7334b79aada:apps/android/app/src/main/res/drawable-nodpi/health_atlas_sensory_" + slug + ".png"],
    {cwd: root, maxBuffer: 32_000_000});
  if (png.subarray(1, 4).toString() !== "PNG" || png.readUInt32BE(16) * 3 !== png.readUInt32BE(20) * 2) throw Error("Invalid portrait " + slug);
  const dir = path.join(assets, "HealthAtlasSensory" + asset + ".imageset");
  fs.writeFileSync(path.join(dir, "cell.png"), png);
  const retired = path.join(dir, "cell.pdf");
  if (fs.existsSync(retired)) fs.unlinkSync(retired);
}
console.log("Imported three original Android #4361 portrait cells.");
