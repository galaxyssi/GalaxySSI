// Source/resource wiring checks, not Swift type checking or actual Canvas playback.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict"),cp=require("node:child_process");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name+".swift"),"utf8");
cp.execFileSync(process.execPath,[path.join(__dirname,"import-body-atlas-function-text.cjs"),"--check"],{cwd:root,stdio:"inherit"});
const catalogue=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")));
for(const language of ["en","zh-Hans"]){
  const map=new Map();
  for(const line of fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").split(/\r?\n/)){
    const m=line.match(/^"([^"]+)" = (".*");$/);if(!m)continue;assert(!map.has(m[1]),m[1]);map.set(m[1],JSON.parse(m[2]));
  }
  assert.equal(map.size,3127);
  for(const s of catalogue.stories)for(const key of [s.title,s.choiceTitle,s.scope,...s.chapters.flatMap(c=>[c.title,c.caption]),...s.references.map(r=>r.title)])assert(map.get(key),language+":"+key);
}
const model=local("GalaxySSIHealthAtlasUptakeMotion"),view=local("GalaxySSIHealthAtlasUptakeView");
const android=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasUptakeView.kt"],{cwd:root,encoding:"utf8"});
const pairs=[["fraction / 0.58","fraction / .58f"],["(fraction - 0.58) / 0.42","(fraction - .58f) / .42f"],
  ["158 + 87 * approach","158f + 87f * approach"],["90 * flatten","90f * flatten"],["fraction * 1.63 - Double(index) * 0.21","fraction * 1.63f - index * .21f"],
  ["radiusY * cos(opening * 0.017453293)","radiusY * cos(opening * DEGREES)"],["relay * 3.5","relay * 3.5f"],
  ["314 - motion.glucoseTravel(index) * 88","314f - travel * 88f"]];
for(const [native,source] of pairs){assert((model+view).includes(native),native);assert(android.includes(source),source);}
for(const route of ["route(87, 40, 119, 14, 151, 21, 169, 45)","route(171, 98, 170, 114, 142, 113, 127, 114)",
  "route(123, 124, 132, 126, 138, 133, 138, 165)","route(293, 179, 293, 203, 228, 186, 228, 214)"])assert(view.includes(route));
for(const token of ["path.trimmedPath","atlas-function-uptake-art","receptor(in: drawing","transporter(in: drawing","motion.flatten == 0","context.draw(Text(verbatim: text)"])assert(view.includes(token),token);
const player=local("GalaxySSIHealthAtlasFunctionPlayer"),panel=local("GalaxySSIHealthAtlasFunctionPanel"),state=local("GalaxySSIHealthAtlasState");
for(const token of ["ProcessInfo.processInfo.systemUptime","durationMs: story.durationMs","scene == .active","!reduceMotion","!previewPresented",
  ".onDisappear { pause() }","if reduceMotion { skip(1); return }","phase = position","onPhase(position)"])assert(player.includes(token),token);
for(const token of ["choices.count > 3","picker.pickerStyle(.menu)","picker.pickerStyle(.segmented)",'.id(entryID + "|" + story.id)',"selection.save"])assert(panel.includes(token),token);
assert(state.includes("private var liveFunctionPhases"));assert(!state.includes("@Published var liveFunctionPhases"));
assert(state.includes("functionSelection?.sanitize"));assert(state.includes("functionSnapshot"));
const detail=local("GalaxySSIHealthAtlasDetail");
assert(detail.includes("selectionSnapshot: { state.functionSnapshot(entry) }"));assert(detail.includes("GalaxySSIHealthAtlasFunctionPanel"));
const registry=local("GalaxySSIHealthAtlasFunctionArtwork");
const enabled=registry.match(/implemented: Set<String> = \[([^\]]+)\]/);assert(enabled);
const enabledIDs=[...enabled[1].matchAll(/"([^"]+)"/g)].map(m=>m[1]),knownIDs=new Set(catalogue.stories.map(s=>s.id));
assert.equal(new Set(enabledIDs).size,enabledIDs.length,"Duplicate enabled course");
for(const id of enabledIDs)assert(knownIDs.has(id),"Enabled course missing from source catalogue: "+id);
assert(registry.includes('implemented: Set<String> = ["GLUCOSE", "HEARTBEAT", "BREATHING", "HEARING", "NEPHRON", "DIGESTION", "COLON", "VISION", "LIGHT_ADAPTATION", "MUSCLE_MOTION", "BONE_REMODELING", "LYMPH_RETURN", "ANTIBODY_RESPONSE", "INSULIN_SECRETION", "GLUCAGON_RESPONSE", "SWEAT_COOLING", "SYNAPTIC_SIGNAL", "MYELIN_SIGNAL", "THYROID_FEEDBACK", "EPIDERMAL_BARRIER", "SPERM_TRANSPORT", "OVUM_TRANSPORT", "OLFACTION", "TASTE_SIGNAL", "TOUCH_SIGNAL", "VESTIBULAR_BALANCE", "RPE_VISUAL_CYCLE", "DIM_LIGHT_RELAY", "CORNEAL_SURFACE_RENEWAL", "AIRWAY_CLEARANCE", "ENDOTHELIAL_EXCHANGE", "PLATELET_HEMOSTASIS", "CARTILAGE_LOAD", "SMOOTH_MUSCLE_WAVE", "TENDON_FORCE_TRANSFER", "ALVEOLAR_SURFACTANT", "INTESTINAL_ABSORPTION", "KNEE_ARTICULATION", "CARDIAC_EXCITATION", "RED_CELL_OXYGEN", "SALIVA_SECRETION", "VENOUS_RETURN", "HAIR_FOLLICLE_CYCLE", "URINE_ROUTE", "PLEURAL_COUPLING", "PARATHYROID_FEEDBACK", "MAMMARY_MILK_FLOW", "CEREBELLAR_COORDINATION", "MELANIN_TRANSFER", "LARYNGEAL_VOICE", "ASTROCYTE_SUPPORT", "SPLENIC_FILTER", "THYMIC_SELECTION", "BRAINSTEM_RHYTHM", "FIBROBLAST_MATRIX", "ARTERIAL_PULSE", "CHONDROCYTE_MATRIX", "ADRENAL_MEDULLA_SIGNAL", "GASTRIC_ACID_SECRETION", "MARROW_HEMATOPOIESIS", "CORONARY_PERFUSION", "PODOCYTE_BARRIER", "ENDOMETRIUM_RENEWAL", "CRANIAL_REFLEX", "SEBUM_RELEASE", "CEREBRAL_SENSORIMOTOR", "AUTONOMIC_RELAY", "GASTRIC_CHIEF_SECRETION", "TONSILLAR_SAMPLING", "ACINAR_ENZYME_SECRETION", "NAIL_MATRIX_GROWTH", "SINUS_DRAINAGE", "TOOTH_MASTICATION", "MESANGIAL_SUPPORT", "INTERCALATED_BALANCE", "CLUB_CELL_AIRWAY", "PANCREATIC_DUCT_BUFFER", "CHOLANGIOCYTE_BILE", "PINEAL_DARK_SIGNAL"]'),"Update coverage audit deliberately when new source renderers land");
console.log("Android #4384 partial player: 2x3127 exact strings, independent persisted/live phase paths, lifecycle/control wiring and dedicated uptake source geometry. Other source renderers are still pending; no native playback executed.");
