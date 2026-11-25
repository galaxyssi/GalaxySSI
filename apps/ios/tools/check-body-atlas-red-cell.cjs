// Pinned geometry/source wiring only; no native compilation or oxygen-transport validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasRedCellStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasRedCellMotion.swift"),view=local("GalaxySSIHealthAtlasRedCellView.swift"),drawing=local("GalaxySSIHealthAtlasRedCellDrawing.swift"),all=motion+view+drawing;
const from=source.match(/private val alveolus = Path\(\).apply \{([^}]+)\}/)[1],to=view.match(/static let alveolus = Path \{ p in([\s\S]*?)\n  \}/)[1];
const expected=[...from.matchAll(/(moveTo|lineTo|cubicTo)\(([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
const actual=[...to.matchAll(/p\.(move|addLine|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))/g)].map(m=>{
  const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
  return m[1]==="addCurve"?["cubicTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
});assert.deepEqual(actual,expected);assert(!to.includes("closeSubpath"));
for(const [swift,kotlin] of [
  ["(safe(t) + (diffuse ? 1 : 0)) * 0.5","(t + if (diffuse) 1f else 0f) * .5f"],
  ["166 + 58 * (peripheralFlow(t, diffuse: diffuse) - 0.5)","exchangeX + 58f * (flow - .5f)"],
  ["(t - 0.09 * Double(index)) / 0.77","(t - .09f * i) / .77f"],
  ["(t - 0.09 * Double(index)) / 0.78","(t - .09f * i) / .78f"],
  ["mix(166 + 20 * lane, 86 + 94 * Double(index), f * f)","mix(exchangeX + 20f * lane, 86f + 94f * i, f * f)"],
  ["mix(plasmaY, 268, f)","mix(plasmaY, 268f, f)"],["mix(10 * lane, 20 * lane, f)","mix(10f * lane, 20f * lane, f)"],
  ["mix(Double(146 + 4 * (index % 2)), plasmaY, f)","mix(146f + 4f * (i % 2), plasmaY, f)"],
  ["mix(116 + 42 * Double(index), x + 10 * Double(index - 1), f)","mix(116f + 42f * i, x + 10f * (i - 1), f)"],
  ["size: 3.35, angle: -11 + 24 * t","3.35f, -11f + 24f * t"],
  ["14 * wave(t * 0.6 + 0.3 * Double(i))","14f * wave(t * .6f + .3f * i)"],
  ["bound == 1 ? 0 : 10 * Double(i - 1)","if (bound == 1) 0f else 10f * (i - 1)"],
  ["startAngle: .degrees(196), endAngle: .degrees(196 + 123)","196f, 123f, false"],
  ["CGAffineTransform(scaleX: 20, y: 10)","-20f, -10f, 20f, 10f"],
  ["wall + 2)","wall + 2f)"],["firstX + 50 * Double(i)","firstX + 50f * i"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["case 0: art.redCellCloseUp(t)","case 1: art.redCellLung(t)","case 2: art.redCellTransport(t)","diffuse: step == 4",
  "redCellVessel(160, 249)","redCellVessel(105, 248, wall: 11)","redCellVessel(98, 189)", "bound: 1, rich: false", "bound: 3",
  "from: rich ? 0xF6A49E : 0xE6A3AC", "to: rich ? 0xC65F6E : 0xA96177", "top: -14, bottom: 14", "top: -7, bottom: 6",
  "disc(x - 2, y, 2.9, RedCellShapes.oxygen", "disc(x + 2, y, 2.9, RedCellShapes.oxygen", "if diffuse"])assert(all.includes(token),token);
for(const color of ["A35264","B47983","1C746D","F6A49E","C65F6E","E6A3AC","A96177","C77884","F6B8AD","FCF6EB","FFDDD6","E6EEE3","B6D6C6","FAEEF1","E9B5BE","C993A4"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(red_cell_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-red-cell-oxygen-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "RED_CELL_OXYGEN": GalaxySSIHealthAtlasRedCellView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["RedCellMotion","RedCellView","RedCellDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 red-cell source audit: five scenes, exact alveolar outline, bound/free oxygen, delayed lung loading, flowing rich/muted cells, continuous plasma-to-tissue handoff and bilingual labels. No native compilation/pixels verified.");
