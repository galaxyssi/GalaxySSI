// Regenerate all twelve current immune plates without restoring retired vectors.
const cp=require("node:child_process"),path=require("node:path");
for(const name of ["painted-innate","painted-granulocytes","immune-links","blood-defense"]){
  cp.execFileSync(process.execPath,[path.join(__dirname,"import-body-atlas-"+name+".cjs")],
    {cwd:path.resolve(__dirname,"../../.."),stdio:"inherit"});
}
