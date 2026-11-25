// Pinned formula/geometry wiring only; no native compilation or lactation-model acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMammaryStoryView.kt"],{cwd:root,encoding:"utf8"});
const primitives=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasBarrierStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasMammaryMotion.swift"),view=local("GalaxySSIHealthAtlasMammaryView.swift"),tissue=local("GalaxySSIHealthAtlasMammaryTissueDrawing.swift"),drawing=local("GalaxySSIHealthAtlasMammaryDrawing.swift"),all=motion+view+tissue+drawing;
for(const [native,android] of [
  ["Self.ease((t - 0.32) / 0.68)","ease((t - .32f) / .68f)"],["1 - Self.ease((t - 0.68) / 0.32)","1f - ease((t - .68f) / .32f)"],
  ["88 - 15 * squeeze","88f - 15f * squeeze"],["amount = 0.14","0 -> .14f"],["amount = 0.14 + 0.24 * t","1 -> .14f + .24f * t"],
  ["amount = 0.38 + 0.62 * Self.ease(t)","2 -> .38f + .62f * ease(t)"],["amount = 1 - 0.65 * Self.ease(t)","else -> 1f - .65f * ease(t)"],
  ["angle * 0.017453293","angle * .017453293f"],["138 + radius * cos(radians)","sacX + r * cos(angle * .017453293f)"],
  ["177 + radius * sin(radians)","sacY + r * sin(angle * .017453293f)"],
  ["(amount - Double(i) / 21) * 12","(amount - i / 21f) * 12f"],["Double(i) * 137.5 + 16","i * 137.5f + 16f"],
  ["radius * (0.37 + 0.09 * Double(i % 4))","r * (.37f + .09f * (i % 4))"],["abs(p.y - 177) >= 11","kotlin.math.abs(y(distance, a) - sacY) < 11f"],
  ["(2.3 + 0.5 * Double(i % 3)) * size","(2.3f + .5f * (i % 3)) * size"],
  ["(t - 0.065 * Double(index)) / 0.38","(t - .065f * i) / .38f"],
  ["radius + 22 + (1 - travel) * (44 - Double(index) * 11)","r + 22f + (1f - travel) * (44f - i * 11f)"],
  ["3.5 * (1 - Self.ease((t - 0.4) / 0.36))","3.5f * (1f - ease((t - .4f) / .36f))"],
  ["safe(t) * 1.52 - Double(index) * 0.115","t * 1.52f - i * .115f"],
  ["193 + (333 - 197) * travel","193f + (ductEnd - 197f) * travel"],
  ["6.5 * (1 - 0.45 * travel)","6.5f * (1f - .45f * travel)"],
  ["48 + 17.6 * Double(i)","48f + 17.6f * i"],["a + 8.8","a + 8.8f"],["13 - 2 * frame.squeeze","13f - 2f * squeeze"],
  ["Int(165 * frame.amount)","(165f * amount).toInt()"]
]){assert(all.includes(native),native);assert(source.includes(android),android);}
for(const token of ["path.move(to: CGPoint(x: 333, y: 201))", "path.addLine(to: CGPoint(x: 275, y: 201))", "control1: CGPoint(x: 246, y: 201)",
  "control2: CGPoint(x: lower.x + 14, y: lower.y - 17)", "startAngle: .degrees(40), endAngle: .degrees(320), clockwise: false",
  "control1: CGPoint(x: upper.x + 14, y: upper.y + 17), control2: CGPoint(x: 246, y: 153)","path.addLine(to: CGPoint(x: 333, y: 153))",
  "startPoint: CGPoint(x: 82, y: 0), endPoint: CGPoint(x: 253, y: 0)","Self.color(0xECCD93).opacity(0)",
  "for i in 0...15", "for row in 0...1", "for i in 0...3", "stride(from: 66, through: 306, by: 40)","for i in 0...18",
  "case 0:", "case 1:", "case 3: mammarySignal(frame, t)", "case 4:", "for i in 0...5", "guard (0...1).contains(travel)"])assert(all.includes(token),token);
assert(source.includes("40f, 280f, false"));assert(source.includes("paint.strokeCap = Paint.Cap.BUTT"));
assert.equal((tissue.match(/lineCap: \.butt/g)||[]).length,2);
const outline=view.match(/static func outline[\s\S]*?var path = Path\(\)([\s\S]*?)\n  \}/)[1];assert(!outline.includes("closeSubpath"));
const ink=primitives.match(/protected fun ink\([^}]+\}/)[0];assert(!ink.includes("strokeCap"));assert(!ink.includes("shader"));
for(const color of ["9D626D","B67581","BA8DA7","609C90","546F73","FFF5D6","A67847","F7D4C5","E6A5AE","FFFCF4","F7ECDA","ECCD93","A8CBB7","DEC4D2"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(mammary_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-mammary-milk-flow-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "MAMMARY_MILK_FLOW": GalaxySSIHealthAtlasMammaryView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["MammaryMotion","MammaryView","MammaryTissueDrawing","MammaryDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 mammary source audit: open arc-to-duct outline, butt-cap gradient wall/transparent milk tint, luminal/basal cells, stored milk, delayed oxytocin/squeeze and finite outflow with bilingual labels. No native compilation/pixels verified.");
