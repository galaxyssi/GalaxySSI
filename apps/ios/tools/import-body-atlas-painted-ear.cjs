// Import the pinned Android painted ear without resampling; retire its generated PDF.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, "../../.."), dir = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasEarSection.imageset");
const bytes = cp.execFileSync("git", ["show", "b513fe5023b8699e4e64e1f914f09be98ddeeacb:apps/android/app/src/main/res/drawable-nodpi/health_atlas_ear_section.png"],
  {cwd: root, maxBuffer: 32_000_000});
if (bytes.subarray(1, 4).toString() !== "PNG" || bytes.readUInt32BE(16) * 2 !== bytes.readUInt32BE(20) * 3) throw Error("Unexpected ear image");
fs.writeFileSync(path.join(dir, "ear.png"), bytes);
const retired = path.join(dir, "ear.pdf");
if (fs.existsSync(retired)) fs.unlinkSync(retired);
console.log("Imported original 3:2 Android #4359 ear bitmap and retired its generated vector PDF.");
