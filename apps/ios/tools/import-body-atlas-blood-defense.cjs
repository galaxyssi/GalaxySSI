// Import Android #4368 original core blood/immune artwork.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="26b7b4395a27a74a3f9e3e45db9c46f217c505f9";
(async()=>{
  for(const [slug,asset] of [["t","TCell"],["b","BCell"],["nk","NaturalKiller"],["megakaryocyte","Megakaryocyte"],["platelet","Platelet"]]){
    const bytes=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/res/drawable-nodpi/health_atlas_cell_"+slug+".png"],{cwd:root,maxBuffer:16_000_000});
    const info=await sharp(bytes).metadata();
    if(info.width!==1254||info.height!==1254||!info.hasAlpha)throw Error("Unexpected blood-defense artwork");
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmune"+asset+".imageset");
    fs.writeFileSync(path.join(dir,"cell.png"),bytes);
    const retired=path.join(dir,"cell.pdf");if(fs.existsSync(retired))fs.unlinkSync(retired);
  }
  console.log("Imported Android #4368 original five blood-defense PNGs.");
})().catch(error=>{console.error(error);process.exitCode=1;});
