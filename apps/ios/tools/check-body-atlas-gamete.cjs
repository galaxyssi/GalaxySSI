// Pinned source/geometry audit only; no Swift execution or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGameteStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasGameteMotion.swift"),view=local("GalaxySSIHealthAtlasGameteView.swift");
const sperm=local("GalaxySSIHealthAtlasSpermDrawing.swift"),ovum=local("GalaxySSIHealthAtlasOvumDrawing.swift"),base=local("GalaxySSIHealthAtlasIllustratedDrawing.swift"),all=motion+view+sperm+ovum;
for(const name of ["rete","epididymis","vas","pickupPath","ampulla"]){
  const block=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const [swift,kotlin] of [
  ["follicleOpens = 0.30","FOLLICLE_OPENS = .30f"],["(safePhase(t) - follicleOpens) / 0.70","(HealthAtlasFunctionStory.safePhase(t) - FOLLICLE_OPENS) / .70f"],
  ["v * v * (3 - 2 * v)","v * v * (3f - 2f * v)"],["16 + 328 * safePhase(t)","16f + 328f * HealthAtlasFunctionStory.safePhase(t)"],
  ["(x - center) / 26","(x - center) / 26f"],["28 - 17 * exp(-distance * distance)","28f - 17f * exp(-distance * distance)"],
  ["t * 1.19 - Double(i) * 0.062","t * 1.19f - .062f * i"],["0.86 + Double(i) * 0.036 + 0.009 * wave(t + Double(i) * 0.2)",".86f + .036f * i + .009f * wave(t + i * .2f)"],
  ["82 + 212 * t, 318 + 4 * wave(3 * t)","82f + 212f * t, 318f + 4f * wave(3f * t)"],
  ["min(328, max(31, 16 + 328 * t))","(16f + 328f * t).coerceIn(31f, 328f)"],
  ["t >= GalaxySSIHealthAtlasGameteMotion.follicleOpens","t >= HealthAtlasGameteMotion.FOLLICLE_OPENS"],
  ["220 + outside * 95","220f + outside * 95f"],["159 - outside * 17","159f - outside * 17f"],
  ["tipX + 19, y: tipY + 5","tipX + 19f, tipY + 5f"],["t * 3.3 - Double(i) * 0.11","t * 3.3f - i * .11f"],
  ["4 * exp(-distance * distance)","4f * exp(-((x - 14f - 330f * t) / 32f) * ((x - 14f - 330f * t) / 32f))"],
  ["63 + 227 * t, 181 + 4 * wave(t)","63f + 227f * t, 181f + 4f * wave(t)"],
  ["0.13 + 0.43 * GalaxySSIHealthAtlasGameteMotion.pickup(t)",".13f + .43f * HealthAtlasGameteMotion.pickup(t)"],
  ["r * 1.43","r * 1.43f"],["curl * 0.66","curl * .66f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["case 0: spermFormation(t)","case 1, 2, 3: spermDuctMap(step: step, t: t)","default: spermPropel(t)"])assert(sperm.includes(token),token);
for(const token of ["case 0, 1: ovary(releasing: step == 1, t: t)","case 2: ovumPickup(t)","case 3: ovumCilia(t)",
  "default: ovumDestination(t)","startAngle: .degrees(52), endAngle: .degrees(321), clockwise: false"])assert(ovum.includes(token),token);
assert(base.includes("min(1, max(0, fraction))"));assert(base.includes("GalaxySSIHealthAtlasFunctionPath.sample"));
assert(!all.includes("Timer"));assert(!all.includes('Image('));
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_((?:sperm|ovum)_flow_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-sperm-transport-art"));assert(view.includes("atlas-function-ovum-transport-art"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SPERM_TRANSPORT", "OVUM_TRANSPORT": GalaxySSIHealthAtlasGameteView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["GameteMotion","GameteView","SpermDrawing","OvumDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 gamete source audit: two five-stage courses, five exact tracks, follicle opening/release/pickup, moving Gaussian duct constriction, formation/epididymal maturation/storage, fimbriae/cilia/ampulla scenes and bounded bilingual labels. No native compilation/pixels verified.");
