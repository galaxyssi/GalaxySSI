// Import Android #4366 original transparent granulocyte artwork.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="3aa202bc663c6d15bc8085a6af965b461f620899";
(async()=>{
  for(const [slug,asset] of [["eosinophil","Eosinophil"],["basophil","Basophil"]]){
    const bytes=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/res/drawable-nodpi/health_atlas_cell_"+slug+".png"],{cwd:root,maxBuffer:16_000_000});
    const info=await sharp(bytes).metadata();
    if(info.width!==1254||info.height!==1254||!info.hasAlpha)throw Error("Unexpected granulocyte resource");
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmune"+asset+".imageset");
    fs.writeFileSync(path.join(dir,"cell.png"),bytes);
    const retired=path.join(dir,"cell.pdf");if(fs.existsSync(retired))fs.unlinkSync(retired);
  }
  console.log("Imported Android #4366 original eosinophil and basophil PNGs.");
})().catch(error=>{console.error(error);process.exitCode=1;});
