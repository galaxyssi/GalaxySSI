// Import the exact current Android #4364 painted section, never the retired vector.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="24748a84e848040dbe0cba323cbd5d6b970fb537";
(async()=>{
  const bytes=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/res/drawable-nodpi/health_atlas_heart_section.png"],{cwd:root,maxBuffer:16_000_000});
  const info=await sharp(bytes).metadata();
  if(info.width!==1254||info.height!==1254||!info.hasAlpha)throw Error("Unexpected cardiac section");
  const directory=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasHeartSection.imageset");
  fs.writeFileSync(path.join(directory,"heart.png"),bytes);
  const retired=path.join(directory,"heart.pdf");if(fs.existsSync(retired))fs.unlinkSync(retired);
  console.log("Imported Android #4364 original 1254x1254 transparent cardiac section.");
})().catch(error=>{console.error(error);process.exitCode=1;});
