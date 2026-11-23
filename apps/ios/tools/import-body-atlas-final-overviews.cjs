// Regenerate current system artwork without restoring the retired nervous PDF.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const sharp = require("sharp"), root = path.resolve(__dirname, "../../..");
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const sha = "5ca99f3dde521cd65ca0f0f84b5550a31da5b9f2";
(async () => {
  const bytes = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/res/drawable-nodpi/health_atlas_system_nervous.png"],
    {cwd: root, maxBuffer: 16_000_000});
  const info = await sharp(bytes).metadata();
  if (info.width !== 1024 || info.height !== 1536 || !info.hasAlpha) throw Error("Unexpected nervous artwork");
  const directory = path.join(assets, "HealthAtlasOverviewNervous.imageset");
  fs.writeFileSync(path.join(directory, "overview.png"), bytes);
  const retired = path.join(directory, "overview.pdf");
  if (fs.existsSync(retired)) fs.unlinkSync(retired);
  cp.execFileSync(process.execPath, [path.join(__dirname, "import-body-atlas-sensory-gradients.cjs"), "--system-overviews"],
    {cwd: root, stdio: "inherit"});
  console.log("Imported Android #4362 posterior nervous PNG and three shaded overview vectors.");
})().catch(error => { console.error(error); process.exitCode = 1; });
