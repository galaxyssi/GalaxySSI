// Copy the pinned Android originals byte-for-byte; no resampling or image generation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, "../../.."), assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const sha = "be7c78beabadc52bbaf41f5576644b58f2decc22";
for (const [name, slug, filename] of [
  ["Pancreas", "pancreas", "pancreas.png"], ["Urinary", "urinary", "urinary.png"], ["Nephron", "nephron", "nephron.png"],
  ["Alveolus", "alveolus", "alveolus.png"], ["BetaCell", "beta_cell", "atlas.png"],
  ["Erythrocyte", "erythrocyte", "atlas.png"], ["Neuron", "neuron", "atlas.png"]
]) {
  const data = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/res/drawable-nodpi/health_atlas_" + slug + ".png"],
    {cwd: root, maxBuffer: 32_000_000});
  if (data.subarray(1, 4).toString() !== "PNG") throw Error("Not PNG: " + name);
  fs.writeFileSync(path.join(assets, "HealthAtlas" + name + ".imageset", filename), data);
}
console.log("Imported seven original Android #4355 editorial illustrations.");
