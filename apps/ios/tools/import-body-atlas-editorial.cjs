// Copy the pinned Android originals byte-for-byte; no resampling or image generation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, "../../.."), assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const sha = "b4ed9ae74fa6989da5addbfdd8bf9d35dd960855";
for (const [name, slug, filename] of [
  ["Body", "body", "atlas.png"], ["Heart", "heart", "atlas.png"], ["Lungs", "lungs", "atlas.png"],
  ["Liver", "liver", "atlas.png"], ["Kidney", "kidney", "atlas.png"], ["Brain", "brain", "atlas.png"], ["Gut", "gut", "gut.png"]
]) {
  const data = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/res/drawable-nodpi/health_atlas_" + slug + ".png"],
    {cwd: root, maxBuffer: 32_000_000});
  if (data.subarray(1, 4).toString() !== "PNG") throw Error("Not PNG: " + name);
  fs.writeFileSync(path.join(assets, "HealthAtlas" + name + ".imageset", filename), data);
}
console.log("Imported seven original Android #4354 editorial illustrations.");
