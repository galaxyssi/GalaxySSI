// Import the pinned Android #4360 eye plate without resampling.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const root = path.resolve(__dirname, "../../.."), dir = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasEyeSection.imageset");
const bytes = cp.execFileSync("git", ["show", "920ede43e4c010f166d459ca2f5e674414766683:apps/android/app/src/main/res/drawable-nodpi/health_atlas_eye_section.png"],
  {cwd: root, maxBuffer: 32_000_000});
if (bytes.subarray(1, 4).toString() !== "PNG" || bytes.readUInt32BE(16) * 2 !== bytes.readUInt32BE(20) * 3) throw Error("Unexpected eye image");
fs.writeFileSync(path.join(dir, "eye.png"), bytes);
const retired = path.join(dir, "eye.pdf");
if (fs.existsSync(retired)) fs.unlinkSync(retired);
console.log("Imported original 3:2 Android #4360 eye bitmap and retired its generated vector PDF.");
