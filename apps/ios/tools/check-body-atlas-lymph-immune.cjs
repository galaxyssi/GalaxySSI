// Source/resource integration only, not Swift execution or native playback.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=(name,rev=sha)=>cp.execFileSync("git",["show",rev+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasLymphImmuneStoryView.kt").toString();
const sections=show("java/com/galaxyssi/chat/HealthAtlasLymphOrgans.kt").toString();
const motion=local("GalaxySSIHealthAtlasLymphImmuneMotion.swift"),view=local("GalaxySSIHealthAtlasLymphImmuneView.swift");
const lymph=local("GalaxySSIHealthAtlasLymphReturnDrawing.swift"),antibody=local("GalaxySSIHealthAtlasAntibodyDrawing.swift");
const all=motion+view+lymph+antibody;
const pack=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasLymphOrgans.dataset/content.json")));
for(const [id,slug] of [["lymph-nodes","node"],["thoracic-duct","duct"]]){
  const block=sections.match(new RegExp('"'+id+'" -> listOf\\(([\\s\\S]*?)\\n        \\)'));assert(block,id);
  const expected=[...block[1].matchAll(/atlasSectionTrack\(([\d.]+)f, ([\d.]+)f\) \{([^}]+)\}/g)].map(m=>({
    start:{x:Number(m[1]),y:Number(m[2])},commands:[...m[3].matchAll(/(lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(c=>{
      const values=c[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")));
      return {kind:{lineTo:"line",quadTo:"quad",cubicTo:"cubic"}[c[1]],
        points:values.reduce((r,x,i)=>{if(i%2===0)r.push({x,y:values[i+1]});return r;},[])};
    })
  }));
  assert.equal(expected.length,4);assert.deepEqual(pack.routes[id],expected,id);
  for(let i=1;i<expected.length;i++)assert.deepEqual(expected[i].start,expected[i-1].commands.at(-1).points.at(-1));
  assert.equal(expected.flatMap(r=>r.commands).length,5);
  const file="res/drawable/health_atlas_lymph_"+slug+".xml";
  assert(show(file).equals(show(file,"b8fbf1191367153af2824506df99bbc5c5bae56e")),slug);
}
for(const [slug,asset] of [["b","HealthAtlasImmuneBCell"],["t","HealthAtlasImmuneTCell"],["plasma","HealthAtlasImmunePlasma"]]){
  const folder=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",asset+".imageset");
  const filename=JSON.parse(fs.readFileSync(path.join(folder,"Contents.json"))).images[0].filename;
  assert(show("res/drawable-nodpi/health_atlas_cell_"+slug+".png").equals(fs.readFileSync(path.join(folder,filename))),asset);
}
for(const [swift,kotlin] of [
  ["fraction * 1.75","safePhase(progress) * 1.75f"],["cycle < 0.41","cycle < .41f"],["cycle < 0.57 || cycle >= 0.97","cycle < .57f || cycle >= .97f"],
  ["cycle / 0.41","cycle / .41f"],["1 - (cycle - 0.57) / 0.40","1f - (cycle - .57f) / .40f"],
  ["fraction < 0.47","t < .47f"],["fraction / 0.47","t / .47f"],["(fraction - 0.47) / 0.53","(t - .47f) / .53f"],
  ["sin(phase * .pi / 2)","sin(phase * PI.toFloat() / 2f)"],["31 + 27 * shift","31f + 27f * shift"],["105 - 20 * shift","105f - 20f * shift"],
  ["t * 1.04 + Double(i) / 6","t * 1.04f + i / 6f"],["t * 1.24 + Double(i) / 6","t * 1.24f + i / 6f"],
  ["6 + 7 * sin(.pi * t)","6f + 7f * sin(PI.toFloat() * t)"],["f < 0.62 ? (f - 0.62) * 9 : (f - 0.62) * 70","if (f < .62f) (f - .62f) * 9f else (f - .62f) * 70f"],
  ["72 + min(f, 0.75) * 145","72f + minOf(f, .75f) * 145f"],["9 + 19 * PumpStage.expansion","9f + 19f * HealthAtlasLymphPumpStage.expansion"],
  ["motion.fraction * 2.6 + Double(i) * 0.25","t * 2.6f + i * .25f"],["t * 1.08 + Double(i) / 9","t * 1.08f + i / 9f"],
  ["294 - 101 * t","294f - 101f * t"],["264 - 15 * t","264f - 15f * t"],["right - 62 - f * (right - 221)","right - 62f - f * (right - 221f)"],
  ["102 + 17 * t","102f + 17f * t"],["98 + 13 * t","98f + 13f * t"],["t > 0.23 + Double(i) * 0.19","t > .23f + i * .19f"],
  ["2 * min(x - 8, 352 - x)","2f * minOf(x - 8f, 352f - x)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["tracks.allSatisfy(\\.valid)","track.start == endpoint","tracks.flatMap(\\.commands)","let l = Int(x - half)",
  "self == .filling","self == .emptying"])assert(motion.includes(token),token);
assert(antibody.includes("mirrored.scaleBy(x: -1, y: 1)"));
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_((?:lymph_flow|antibody_story)_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--tissue-lymph"],{cwd:root,stdio:"inherit"});
assert(view.includes("atlas-function-lymph-return-art"));assert(view.includes("atlas-function-antibody-response-art"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "LYMPH_RETURN", "ANTIBODY_RESPONSE": GalaxySSIHealthAtlasLymphImmuneView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["LymphImmuneMotion","LymphImmuneView","LymphReturnDrawing","AntibodyDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 lymph/antibody source audit: two five-stage courses, inlet/outlet cycle, joined original section paths, retained gradients, original B/T/plasma images, clone split/differentiation/release and bounded bilingual labels. Native rendering/compilation unverified.");
