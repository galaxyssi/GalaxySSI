// Copy the ten final bitmap revisions from pinned Android #4357, without resampling.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, "../../.."), assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const sha = "96b3f950e85c839173e473ddb2435fe88f1acb75";
for (const [asset, slug, filename] of [
  ["SkeletonFront", "skeleton_front", "artwork.png"], ["SkeletonBack", "skeleton_back", "artwork.png"],
  ["MuscleFront", "muscle_front", "artwork.png"], ["MuscleBack", "muscle_back", "artwork.png"],
  ["OverviewSensory", "system_sensory", "overview.png"], ["OverviewRespiratory", "system_respiratory", "overview.png"],
  ["OverviewDigestive", "system_digestive", "overview.png"], ["OverviewEndocrine", "system_endocrine", "overview.png"],
  ["OverviewImmune", "system_immune", "overview.png"], ["OverviewSkin", "system_skin", "overview.png"]
]) {
  const bytes = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/res/drawable-nodpi/health_atlas_" + slug + ".png"],
    {cwd: root, maxBuffer: 32_000_000});
  if (bytes.subarray(1, 4).toString() !== "PNG") throw Error("Not PNG: " + asset);
  fs.writeFileSync(path.join(assets, "HealthAtlas" + asset + ".imageset", filename), bytes);
}
console.log("Imported ten final original Android #4357 bitmap revisions.");
