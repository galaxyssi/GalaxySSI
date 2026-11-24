// Source/formula/resource checks only; not execution of Swift models, drawing, or XCTest.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n+".swift"),"utf8");
const source=n=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/"+n+".kt"],{cwd:root,encoding:"utf8"});
const kotlin=source("HealthAtlasPhysiology"),native=local("GalaxySSIHealthAtlasPhysiology");
const diagram=source("HealthAtlasMaterialResponseView"),drawing=local("GalaxySSIHealthAtlasMaterialResponseDrawing"),view=local("GalaxySSIHealthAtlasMaterialResponseView");
const text=local("GalaxySSIHealthAtlasPhysiologyText"),panel=local("GalaxySSIHealthAtlasPhysiologyPanel");
const norm=s=>s.replace(/\s+/g,"");
function block(s,from){const at=s.indexOf(from);assert(at>=0,from);let start=s.indexOf("(",at),depth=0;for(let i=start;i<s.length;i++){if(s[i]==="(")depth++;else if(s[i]===")"&&!--depth)return s.slice(start+1,i);}assert.fail(from);}
const mapping=[
 ["ALVEOLAR_DIFFUSION","alveolarDiffusion",["diffusion_gradient","diffusion_area","diffusion_thickness"],["respiratory-membrane","pulmonary-capillaries","tissue-alveolar-epithelium","cell-type-i-pneumocyte"]],
 ["CARTILAGE_COMPRESSION","cartilageCompression",["compression_stress","compression_modulus"],["cartilage","tissue-hyaline-cartilage","cell-chondrocyte"]],
 ["BONE_BENDING","boneBending",["bone_bending_moment","bone_bending_diameter","bone_bending_cavity"],["limb-bones","femur","tibia","fibula"]]
];
const specs=new Map();
for(const [android,swift,keys,owners]of mapping){
 const declaration=block(kotlin,android+"(listOf(");
 const inputs=[...declaration.matchAll(/HealthAtlasInput\("([^"]+)", (\d+)\.\.(\d+), (\d+)(?:, ([\d.]+))?\)/g)].map(m=>({key:m[1],low:+m[2],high:+m[3],initial:+m[4],scale:+(m[5]||1)}));
 assert.equal(inputs.length,keys.length);
 const start=native.indexOf("case ."+swift+":"),end=native.indexOf("\n      case ",start+1),swiftInputs=native.slice(start,end);
 inputs.forEach((spec,i)=>{
  assert(swiftInputs.includes('key: "'+keys[i]+'"'));
  assert(swiftInputs.includes("range: "+spec.low+"..."+spec.high+", initial: "+spec.initial));
  if(spec.scale!==1)assert(swiftInputs.includes("scale: "+spec.scale+","));
 });
 for(const owner of owners){assert(kotlin.includes('"'+owner+'"'));assert(native.includes('"'+owner+'"'));}
 specs.set(swift,inputs);
}
for(const [a,b]of [
 ["values[0] * values[1] / values[2]","values[0] * values[1] / values[2]"],
 ["values[0] / (10.0 * values[1])","values[0] / (10 * values[1])"],
 ["500.0 * values[0] * values[1] / circularSectionMoment(values[1], values[2])","500 * values[0] * values[1] / Self.circularSectionMoment(diameter: values[1], innerRatio: values[2])"],
 ["Math.PI * diameter.pow(4) * (1 - innerRatio.pow(4)) / 64.0",".pi * pow(diameter, 4) * (1 - pow(innerRatio, 4)) / 64"]
]){assert(norm(kotlin).includes(norm(a)),a);assert(norm(native).includes(norm(b)),b);}
assert(native.includes("case .alveolarDiffusion: return input(1) / input(2)"));
assert(native.includes("case .cartilageCompression: return 100 - result"));
assert(native.includes("case .boneBending: return Self.circularSectionMoment(diameter: input(1), innerRatio: input(2))"));
const inertia=(d,r)=>Math.PI*d**4*(1-r**4)/64;
const evaluate=(kind,v)=>kind==="alveolarDiffusion"?v[0]*v[1]/v[2]:kind==="cartilageCompression"?v[0]/(10*v[1]):500*v[0]*v[1]/inertia(v[1],v[2]);
let cases=0;
for(const [kind,inputs]of specs){
 const choices=inputs.map(s=>[s.low,s.initial,s.high].map(n=>n/s.scale));
 const combinations=choices.reduce((out,list)=>out.flatMap(values=>list.map(value=>[...values,value])),[[]]);
 for(const values of combinations){
  const result=evaluate(kind,values);assert(Number.isFinite(result)&&result>=0&&result<=(kind==="boneBending"?26:8));cases++;
 }
}
assert.equal(evaluate("alveolarDiffusion",[1,1,1]),1);assert.equal(evaluate("cartilageCompression",[32,1.6]),2);
assert.equal(evaluate("alveolarDiffusion",[0,2,0.5]),0);assert.equal(evaluate("boneBending",[0,20,0.8]),0);
for(const pair of [
 ["13f * model.input(2)","13 * model.input(2)"],["40f * model.input(1)","40 * model.input(1)"],
 ["1.25f + .14f * model.result.toFloat()","1.25 + 0.14 * model.result"],["62 + strain * 1.85f","62 + strain * 1.85"],
 ["model.input(0).toFloat() / 64","model.input(0) / 64"],["1.1f + stress * 1.7f","1.1 + stress * 1.7"],
 ["model.input(1) * 1.3","model.input(1) * 1.3"],["65f * strength","65 * strength"]
]){assert(diagram.includes(pair[0]),pair[0]);assert(drawing.includes(pair[1]),pair[1]);}
assert(diagram.includes("Path.FillType.EVEN_ODD"));assert(drawing.includes("FillStyle(eoFill: true)"));
assert(diagram.includes("(125 * strength).roundToInt()"));assert(drawing.includes("Int((125 * strength).rounded())"));
assert(drawing.includes("for i in 0..<transfers"));assert(drawing.includes("model.result == 0 ? 0"));
assert(drawing.includes("if stress > 0"));assert(drawing.includes("for dx in -5...5"));
assert(drawing.includes("context.fill(tip"));assert(drawing.includes("max(1, natural)"));
for(const token of ["atlas-diffusion-layer","atlas-cartilage-compression","atlas-bone-bending"])assert(view.includes(token));
assert(view.includes("size.width / 340, size.height / 156"));assert(view.includes("measuredWidth * 0.51 * displayScale"));
assert(panel.includes("if model.kind.hasMaterialResponse"));
const beforeControls=panel.indexOf("!model.kind.hasMaterialResponse { chartAndAxis(model) }"),controls=panel.indexOf("ForEach(Array(model.kind.inputs.enumerated())"),afterControls=panel.indexOf("|| model.kind.hasMaterialResponse { chartAndAxis(model) }");
assert(beforeControls>0&&beforeControls<controls&&afterControls>controls);
// This audit remains pinned to the original three #4384 diagrams; #4385 audits calf labels separately.
const keys=[...new Set([...drawing.matchAll(/label\("((?:diffusion|compression|bone_bending)_[^"]+)"/g)].map(m=>"health_atlas_"+m[1]))];
assert.equal(keys.length,8);
for(const language of ["en","zh-Hans"]){
 const strings=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8");
 for(const key of keys)assert(strings.includes('"'+key+'"'),language+":"+key);
 for(const prefix of ["diffusion","compression","bone_bending"])for(const suffix of ["title","scope","formula","diagram"])assert(strings.includes('"health_atlas_'+prefix+"_"+suffix+'"'));
}
for(const url of ["https://pubmed.ncbi.nlm.nih.gov/8210754/","https://pmc.ncbi.nlm.nih.gov/articles/PMC2106384/","https://pubmed.ncbi.nlm.nih.gov/7054208/","https://pubmed.ncbi.nlm.nih.gov/7382457/","https://pmc.ncbi.nlm.nih.gov/articles/PMC8933494/"]){assert(kotlin.includes(url));assert(native.includes(url));}
assert(text.includes('if ["diffusion_", "compression_", "bone_bending_"].contains'));
assert(text.includes('"diffusion_conductance"'));assert(text.includes('"compression_remaining"'));assert(text.includes('"bone_bending_inertia"'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const file of ["GalaxySSIHealthAtlasMaterialResponseView","GalaxySSIHealthAtlasMaterialResponseDrawing"])assert.equal(pbx.split("path = "+file+".swift;").length-1,1);
console.log("Android #4384 material responses: eight input specs/11 owners, three exact formula/source pairs, "+cases+" analytic boundary combinations, dedicated diffusion/compression/bending geometry, controls-before-chart and bilingual text. Swift/XCTest/native pixels not executed.");
