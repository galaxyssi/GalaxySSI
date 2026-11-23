// Import current painted innate-cell resources; retain their original bytes.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="8ac01038b80a341c2c2f4912a455e834cd434daf";
(async()=>{
  for(const [slug,asset] of [["macrophage","Macrophage"],["neutrophil","Neutrophil"]]){
    const bytes=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/res/drawable-nodpi/health_atlas_cell_"+slug+".png"],{cwd:root,maxBuffer:16_000_000});
    const info=await sharp(bytes).metadata();
    if(info.width!==1254||info.height!==1254||!info.hasAlpha)throw Error("Unexpected innate cell");
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmune"+asset+".imageset");
    fs.writeFileSync(path.join(dir,"cell.png"),bytes);
    const retired=path.join(dir,"cell.pdf");if(fs.existsSync(retired))fs.unlinkSync(retired);
  }
  console.log("Imported Android #4365 original macrophage and neutrophil PNGs.");
})().catch(error=>{console.error(error);process.exitCode=1;});
