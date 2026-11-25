// Pinned geometry/timing/resource checks only; no native compilation or cholangiocyte validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCholangiocyteStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["GalaxySSIHealthAtlasCholangiocyteGeometry.swift","GalaxySSIHealthAtlasCholangiocyteRoutes.swift","GalaxySSIHealthAtlasCholangiocyteLabelsDrawing.swift","GalaxySSIHealthAtlasCholangiocyteMotion.swift","GalaxySSIHealthAtlasCholangiocyteGlyphDrawing.swift","GalaxySSIHealthAtlasCholangiocyteWallDrawing.swift","GalaxySSIHealthAtlasCholangiocyteAnatomyDrawing.swift","GalaxySSIHealthAtlasCholangiocyteTransportDrawing.swift","GalaxySSIHealthAtlasCholangiocyteCarryDrawing.swift","GalaxySSIHealthAtlasCholangiocyteView.swift"];
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});

const helpers=Object.fromEntries([...source.matchAll(/private fun Path\.(\w+)\(\) \{([^}]+)\}/g)].map(m=>[m[1],m[2]]));
const expand=b=>b.replace(/(\w+)\(\)/g,(m,n)=>helpers[n]||m);
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)];
assert.equal(shapes.length,21);
const geometry=local("GalaxySSIHealthAtlasCholangiocyteGeometry.swift");
for(const [,name,block] of shapes){
  const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(expand(block)),name);
}
const routeFile=local("GalaxySSIHealthAtlasCholangiocyteRoutes.swift");
const ribbons=[...source.matchAll(/track\(shape \{([^}]+)\}/g)].slice(2,5);
const routes=[
  ["orientLeft",helpers.leftDuct+helpers.downDuct],
  ["orientRight",helpers.rightDuct+helpers.downDuct],
  ...ribbons.map((m,i)=>["ribbon"+i,m[1]]),
  ...["bicarbonate","chloride","water"].map(n=>[n+"Track",shapes.find(m=>m[1]===n+"Course")[2]]),
  ["downstream",source.match(/private val downstream = track\(shape \{([^}]+)\}/)[1]]
];
assert.equal(routes.length,9);
for(const [name,body] of routes){
  const native=routeFile.match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const cmds=[["moveTo",norm(start[1]),norm(start[2])],...[...native.matchAll(/kind: \.(line|quad|cubic), points: \[([^\n]+)\]/g)].map(m=>[
    {line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))])];
  assert.deepEqual(cmds,fromCommands(expand(body)),name);
}
const labels=local("GalaxySSIHealthAtlasCholangiocyteLabelsDrawing.swift");
const calls=[...source.matchAll(/callout\(c, R.string.health_atlas_(\w+),([\s\S]*?)\)/g)];
assert.equal(calls.length,14);
for(const [,key,values] of calls) assert(norm(labels).includes(norm('cholangiocyteCallout("'+key+'",'+values+')')),key);
for(const fragment of [
  "safe(t) * 0.67 + offset", "p - floor(p)",
  "0.035 + Double(index) * 0.18, 0.58", "0.02 + Double(index) * 0.12, 0.60", "p * p * (3 - 2 * p)",
  "if p > 0", "max(0, (p-0.9)*10)",
  "x-fan*(10+Double(i)*13)", "y+fan*13", "x+fan*Double(i)*4", "y+fan*(4+Double(i)*8)",
  "x+fan*Double(i)*8", "y+fan*(Double(i % 2)*11-4)",
  "w/60", "h/95", "138+Double(i)*0.7, 44, -45", "208+Double(i)*0.7, 44, 50, i == 4",
  "path.trimmedPath(from: p, to: min(1, p+span))", "if p+span > 1",
  "path.trimmedPath(from: 0, to: p+span-1)", "0.025+0.95*f", "Double(i % 3-1)*4.8",
  "case 0: cholangiocyteWater", "case 2: cholangiocyteBicarbonate", "default: cholangiocyteBile",
  "cholangiocytePore(214, 153)", "cholangiocytePore(199, 246)",
  'accessibilityIdentifier("atlas-function-cholangiocyte-bile-art")'
]) assert(norm(all).includes(norm(fragment)),fragment);
const advance=(t,start,span)=>{const p=Math.max(0,Math.min(1,(t-start)/span));return p*p*(3-2*p);};
for(let i=0;i<4;i++){
  const start=.02+i*.12;
  assert.equal(advance(start,start,.60),0);
  assert(Math.abs(advance(start+.60,start,.60)-1)<1e-12);
  assert(Math.abs(advance(start+.30,start,.60)-.5)<1e-12);
}
for(let i=0;i<3;i++){
  const start=.035+i*.18;
  assert.equal(advance(start,start,.58),0);
  assert(Math.abs(advance(start+.58,start,.58)-1)<1e-12);
}
for(const p of [0,.15,.7,.95]) {
 const span=.31;
 const intervals=p+span>1?[[p,1],[0,p+span-1]]:[[p,p+span]];
 assert(Math.abs(intervals.reduce((a,[x,y])=>a+y-x,0)-span)<1e-12);
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"));
const story=data.stories.find(s=>s.id==="CHOLANGIOCYTE_BILE");
assert.equal(story.durationMs,20000);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["enter","line","exchange","water","carry"]);
assert.deepEqual(story.references.map(r=>r.url),["https://pubmed.ncbi.nlm.nih.gov/20041402/","https://pubmed.ncbi.nlm.nih.gov/7528928/"]);
for(const ref of story.references) assert(source.includes(ref.url));
for(const lang of ["en","zh-Hans"]) {
 const text=local(lang+".lproj/AtlasFunction.strings");
 for(const [,key] of calls) assert(text.includes('"health_atlas_'+key+'"'),lang+":"+key);
}
const registry=local("GalaxySSIHealthAtlasFunctionArtwork.swift");
assert(registry.includes('case "CHOLANGIOCYTE_BILE": GalaxySSIHealthAtlasCholangiocyteView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names) {
 assert.equal(pbx.split("path = "+name+";").length-1,1,name);
 assert.equal(pbx.split(name+" in Sources").length-1,2,name);
 assert(Buffer.byteLength(local(name))<16000,name);
}
console.log("Android #4384 cholangiocyte: 21 expanded outlines, 9 ordered routes, 14 bilingual callouts, motion windows/wrapped streams and registry checked; no native compilation/pixels verified.");
