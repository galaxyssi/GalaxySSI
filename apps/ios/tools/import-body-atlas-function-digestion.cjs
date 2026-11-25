// Dedicated #4384 Function artwork; existing structure plates retain their pinned geometry.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const sharp=require("sharp"),root=path.resolve(__dirname,"../../..");
(async()=>{
  cp.execFileSync(process.execPath,[path.join(__dirname,"import-body-atlas-sensory-gradients.cjs"),"--function-digestion"],
    {cwd:root,stdio:"inherit"});
  const bytes=cp.execFileSync("git",["show","ab78711d467c013444883dbaeca23c39a601c875:apps/android/app/src/main/res/drawable-nodpi/health_atlas_gut_jejunum.png"],{cwd:root,maxBuffer:20_000_000});
  const info=await sharp(bytes).metadata();
  if(info.width!==1254||info.height!==1254||!info.hasAlpha)throw Error("Unexpected jejunal artwork");
  const directory=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionGutJejunum.imageset");
  fs.mkdirSync(directory,{recursive:true});fs.writeFileSync(path.join(directory,"art.png"),bytes);
  fs.writeFileSync(path.join(directory,"Contents.json"),JSON.stringify({
    images:[{filename:"art.png",idiom:"universal"}],info:{author:"xcode",version:1}
  },null,2)+"\n");
  console.log("Imported original 1254x1254 #4384 jejunal PNG.");
})().catch(error=>{console.error(error);process.exitCode=1;});
