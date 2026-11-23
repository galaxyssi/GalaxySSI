// Import Android #4367 original painted recruitment/presentation/secretion plates.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="20de8dd75a18c257e7a8fdba844511d3bd98c37d";
(async()=>{
  for(const [slug,asset] of [["monocyte","Monocyte"],["dendritic","Dendritic"],["plasma","Plasma"]]){
    const bytes=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/res/drawable-nodpi/health_atlas_cell_"+slug+".png"],{cwd:root,maxBuffer:16_000_000});
    const info=await sharp(bytes).metadata();
    if(info.width!==1254||info.height!==1254||!info.hasAlpha)throw Error("Unexpected immune-link artwork");
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmune"+asset+".imageset");
    fs.writeFileSync(path.join(dir,"cell.png"),bytes);
    const retired=path.join(dir,"cell.pdf");if(fs.existsSync(retired))fs.unlinkSync(retired);
  }
  console.log("Imported Android #4367 original monocyte, dendritic and plasma cell PNGs.");
})().catch(error=>{console.error(error);process.exitCode=1;});
