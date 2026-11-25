// Pinned formula/geometry wiring audit only; not Swift execution or native pixel acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCartilageStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasCartilageMotion.swift"),view=local("GalaxySSIHealthAtlasCartilageView.swift"),drawing=local("GalaxySSIHealthAtlasCartilageDrawing.swift"),all=motion+view+drawing;
for(const [swift,kotlin] of [
  ["case 1: depth = max(0, 23 * f - 16)","1 -> (23f * f - GAP).coerceAtLeast(0f)"],
  ["case 2: depth = 7 + 14 * f","2 -> 7f + 14f * f"],["case 3: depth = 21 - 4 * f","3 -> 21f - 4f * f"],
  ["case 4: depth = 17 * (1 - f)","4 -> 17f * (1f - f)"],
  ["step == 1 ? 23 * f : step == 2 ? 16 + depth : step == 3 ? 37 * (1 - f) : 0","3 -> 37f * (1f - f)"],
  ["step == 1 ? depth / 7 : step == 2 ? 1 - 0.83 * f : step == 3 ? 0.17 * (1 - f) : 0","3 -> .17f * (1f - f)"],
  ["168 - 0.0034 * offsetSquared(x)","168f - .0034f * offsetSquared(x)"],
  ["245 - 0.0007 * offsetSquared(x)","245f - .0007f * offsetSquared(x)"],
  ["rest = 184 - 0.0005 * radiusSquared","rest = 184f - .0005f * radiusSquared"],
  ["depth - 0.0029 * radiusSquared, edge = min(3, depth * 0.5)","overlap = depth - .0029f * radiusSquared"],
  ["overlap >= edge ? overlap : overlap <= -edge ? 0 : (overlap + edge) * (overlap + edge) / (4 * edge)","else -> (overlap + edge) * (overlap + edge) / (4f * edge)"],
  ["top + (baseY(x) - top) * fraction","top + (baseY(x) - top) * fraction"],
  ["Double(row) * 0.23","row * .23f"],["8 * wave(t + Double(i) * 0.21)","8f * wave(t + i * .21f)"],
  ["0.32 + 0.20 * Double(i % 3)",".32f + .20f * (i % 3)"],["0.08 * wave(t + Double(i) * 0.21 + 0.25)",".08f * wave(t + i * .21f + .25f)"],
  ["Int(150 * motion.pressure)","(150f * pressure).toInt()"],
  ["180 + Double(side) * 22","CENTER + side * 22f"],["180 + Double(side) * 76","CENTER + side * 76f"],["180 + Double(side) * 110","CENTER + side * 110f"],
  ["matrixY(start, depth: depth, fraction: 0.43)","matrixY(start, depth, .43f)"],
  ["matrixY(bend, depth: depth, fraction: 0.55)","matrixY(bend, depth, .55f)"],
  ["faceY(exit, depth: depth) + 25","faceY(exit, depth) + 25f"],["faceY(exit, depth: depth) - 8","faceY(exit, depth) - 8f"],
  ["0.04 + 0.92 * (safe(t) * 1.4 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)",".04f + .92f * ((t * 1.4f + i * .5f) % 1f)"],
  ["head = returning ? 1 - f : f, tail = head + (returning ? 0.18 : -0.18)","head + if (returning) .18f else -.18f"],
  ["Int(255 * min(1, (1 - safe(t)) * 4))","(255f * opacity).toLong()"],
  ["y = 68 + travel - (arriving ? 9 * (1 - t) : 0)","68f + travel - if (arriving) 9f * (1f - t) else 0f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["step == 1 || step == 2","step == 2 || step == 4", "returning: step == 4", "boneClip.clip(to: bone)","bandClip.clip(to: band)",
  "stride(from: 36, through: 328, by: 4)","stride(from: 328, through: 32, by: -4)",
  "stride(from: 292, through: 68, by: -4)","stride(from: 72, through: 292, by: 4)","for row in 1...3","for i in 0...11",
  "guard alpha > 0 else { return }","local.opacity *= Double(alpha) / 255","at(route, tail)","at(route, head)"])assert(all.includes(token),token);
for(const color of ["9B745C","346F98","A26030","739292","FFEDDB","E1BA99","E4BD9E","FFEBCF","D4EFE6","A3CABE","75BACC","79AFA0","B7DDCF"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(cartilage_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-cartilage-load-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CARTILAGE_LOAD": GalaxySSIHealthAtlasCartilageView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["CartilageMotion","CartilageView","CartilageDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 cartilage source audit: five stages, local smoothed indentation/fixed bone attachment, patellar travel/load, clipped matrix/water, two shoulder flow routes with return/fade and bilingual annotations. No native compilation/pixels verified.");
