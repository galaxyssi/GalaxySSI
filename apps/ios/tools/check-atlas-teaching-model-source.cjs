// Declaration/source wiring checks only. Does not execute or type-check Swift or native UI.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), crypto = require("node:crypto"), assert = require("node:assert/strict");
const transport = process.argv.includes("--transport-4405"), regional = process.argv.includes("--regional-4402"), organ = process.argv.includes("--organ-4401"), system = process.argv.includes("--system-4399"), revision = transport ? 4405 : regional ? 4402 : organ ? 4401 : system ? 4399 : 4397;
const root = path.resolve(__dirname, "../../.."), sha = transport ? "82d853f1d3d9c7e3455e732771f876a911fd0ce7" : regional ? "0d0112b055947c3747c7910b255aa299587dfd75" : organ ? "e228e379f307fcd6c1eb93b289126e9c473ddf7e" : system ? "de05fd51ba151789acd24dc4484d7f84d893aea3" : "40776e7a67ebfe48c76f98d392849edb9810ac82";
const read = name => fs.readFileSync(path.join(root, "apps/ios", name), "utf8");
const source = name => read("GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift");
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 32_000_000});
const declarations = JSON.parse(read(`ANDROID_${revision}_MODEL_DECLARATIONS.json`)), inventory = JSON.parse(read(`ANDROID_${revision}_SOURCE_INVENTORY.json`));
assert.deepEqual(declarations.source, {androidPR: revision, mergeCommit: sha}); assert.deepEqual(inventory.source, declarations.source);
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(inventory.files.length, changed.length);
for (const [i, [status, file]] of changed.entries()) assert.deepEqual(inventory.files[i], {path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")});
assert.equal(declarations.models.length, 9);
const controls = declarations.models.flatMap(m => m.inputs), owners = declarations.models.flatMap(m => m.entryIDs);
assert.equal(controls.length, transport || regional || organ || system ? 18 : 24); assert.equal(new Set(controls.map(c => c.key)).size, controls.length);
assert.equal(owners.length, transport ? 24 : regional ? 19 : organ ? 42 : system ? 35 : 34); assert.equal(new Set(owners).size, owners.length);
const graph = JSON.parse(git(["show", sha + ":apps/android/app/src/main/assets/health/body-atlas.json"]));
const graphIDs = new Set(graph.entries.map(e => e.id)); for (const id of owners) assert(graphIDs.has(id), id);
const metadata = source("TeachingModel"), inputSource = source("TeachingControls"), values = source("TeachingValues"), physiology = source("Physiology");
const normalize = s => s.replace(/\s+/g, "");
const swiftString = s => JSON.stringify(s).replace(/[^\x00-\x7f]/g, c => "\\u{" + c.charCodeAt(0).toString(16).padStart(4, "0") + "}");
const property = (name, next) => metadata.split("\n  var " + name + ":")[1]?.split("\n  var " + next + ":")[0];
const caseBody = (text, id) => [...text.matchAll(/case ([^:]+):([^]*?)(?=\n\s*(?:case |default:)|$)/g)]
  .find(m => [...m[1].matchAll(/\.(\w+)/g)].some(c => c[1] === id))?.[2];
const unitBody = property("unit", "bounds"), boundsBody = property("bounds", "digits");
const prefixBody = property("resourcePrefix", "title"), companionBody = property("companionTitle", "entryIDs");
const ownersBody = property("entryIDs", "sources"), sourcesBody = property("sources", "unused").split("static func forEntry")[0];
const axisBody = property("axis", "unit");
const axisOne = new Set([...axisBody.match(/case ([^:]+): return 1/)[1].matchAll(/\.(\w+)/g)].map(m => m[1]));
for (const model of declarations.models) assert.equal(axisOne.has(model.id), model.axis === 1);
assert(axisBody.includes("default: return 0"));
const resourceKeys = new Set();
for (const model of declarations.models) {
  const prefix = model.title.replace(/_title$/, "");
  assert(normalize(caseBody(prefixBody, model.id)).startsWith("return" + JSON.stringify(prefix)));
  assert(physiology.includes(model.id));
  const companionSuffix = caseBody(companionBody, model.id)?.match(/suffix = "([^"]+)"/)?.[1] ?? "companion";
  assert.equal(model.companionTitle, prefix + "_" + companionSuffix);
  assert(normalize(caseBody(unitBody, model.id)).startsWith("return" + swiftString(model.unit)));
  assert(normalize(caseBody(boundsBody, model.id)).replace(/_/g, "").startsWith("return" + model.minimum + "..." + model.maximum));
  assert.deepEqual(new Set([...caseBody(ownersBody, model.id).matchAll(/"([^"]+)"/g)].map(m => m[1])), new Set(model.entryIDs));
  assert.deepEqual([...caseBody(sourcesBody, model.id).matchAll(/"(https:[^"]+)"/g)].map(m => m[1]), model.sources);
  assert.equal(model.scope, prefix + "_scope"); assert.equal(model.formula, prefix + "_formula");
  assert.equal(model.digits, Number((caseBody(property("digits", "resourcePrefix"), model.id) ?? "return 2").match(/return (\d)/)[1]));
  for (const key of [model.title, model.scope, model.formula, model.companionTitle]) resourceKeys.add(key);
  const segment = inputSource.split("case ." + model.id + ":")[1]?.split(/\n\s*case /)[0]; assert(segment, model.id);
  for (const control of model.inputs) {
    assert(!/[?\ufffd]/.test(control.unit), "Corrupted unit encoding: " + control.key);
    assert(control.label.startsWith(prefix + "_")); resourceKeys.add(control.label);
    const label = control.label.slice(prefix.length + 1);
    const expected = "control(" + [swiftString(control.key), swiftString(label), control.minimum + "..." + control.maximum,
      control.initial, swiftString(control.unit), ...(control.scale === 1 ? [] : ["scale: " + control.scale]),
      ...(control.digits === 2 ? [] : ["digits: " + control.digits])].join(", ") + ")";
    assert(normalize(segment).includes(normalize(expected)), expected);
  }
}
const formulas = transport ? {
  ureterDelivery: ["values[0].rounded() * values[1]", "(6 - values[0].rounded()) * values[1]"],
  cornealRefraction: ["asin(sin(values[0] * .pi / 180) / values[1]) * 180 / .pi", "values[0] - asin(sin(values[0] * .pi / 180) / values[1]) * 180 / .pi"],
  externalEarResonance: ["values[1] / (4 * (values[0] / 100))", "4 * values[0]"],
  neuralRelayDelays: ["values[0] * values[1]", "(values[0] - 1) * values[1]"],
  biliaryFlowTally: ["values[0] * values[1]", "values[0] * values[1] * 4"],
  parathyroidSignalOccupancy: ["100 * (values[0] / (values[0] + values[1]))", "100 - 100 * (values[0] / (values[0] + values[1]))"],
  follicleSurface: ["4 * .pi * pow(values[0] / 2 + values[1], 2)", "(4 * .pi / 3) * (pow(values[0] / 2 + values[1], 3) - pow(values[0] / 2, 3))"],
  jointArticularArc: ["values[1] * (values[0] * .pi / 180)", "values[0] * .pi / 180"],
  sweatDuctBalance: ["values[0] - values[0] * (values[1] / 100)", "values[0] * (values[1] / 100)"]
} : regional ? {
  bladderExpansion: ["100 * (pow(1 + values[1] / values[0], 2.0 / 3.0) - 1)", "4 * .pi * pow(cbrt(3 * (values[0] + values[1]) / (4 * .pi)), 2)"],
  vestibularTilt: ["atan2(values[0], values[1]) * 180 / .pi", "hypot(values[0], values[1])"],
  airwayCiliaryClearance: ["values[0] * values[1]", "100 * (values[0] * values[1]) / 60"],
  gastricLiquidEmptying: ["100 * pow(1 - values[0] / 100, values[1])", "100 - 100 * pow(1 - values[0] / 100, values[1])"],
  bileStorage: ["values[0] / (12 - values[1])", "values[0]"],
  thoracicCrossSection: [".pi * values[0] * values[1] / 4", "values[0] / values[1]"],
  plateletFragmentCount: ["values[0].rounded() * values[1].rounded()", "values[1].rounded()"],
  boneRemodelingBalance: ["values[1] - values[0]", "100 + values[1] - values[0]"],
  cutaneousSebum: ["values[0] / values[1]", "values[0]"]
} : organ ? {
  arterialContinuity: ["values[1] / (.pi * pow(values[0] / 20, 2))", ".pi * pow(values[0] / 20, 2)"],
  glialCapacitance: ["values[1] * (log1p(0.5) / log1p(values[0] * 0.5))", "log1p(0.5) / log1p(values[0] * 0.5)"],
  colonicWaterBalance: ["values[0] - values[0] * (values[1] / 100)", "values[0] * (values[1] / 100)"],
  lymphParticleTransport: ["values[1] * values[0]", "values[1] * values[0] * 5"],
  endocrineDilution: ["values[0] / values[1]", "values[0]"],
  boneSection: ["values[0] / (.pi * (25 - pow(5 - values[1], 2)))", ".pi * (25 - pow(5 - values[1], 2))"],
  retinalConvergence: ["values[0] * (values[1] / 100)", "values[0] * (1 - values[1] / 100)"],
  muscleShortening: ["values[0] * values[1] / 1000", "values[0] * (2.5 - values[1]) / 1000"],
  keratinGrowth: ["values[0] * values[1]", "1 / values[1]"]
} : system ? {
  diaphragmDisplacement: ["values[1] * values[0] / 10", "values[1] / 10"],
  cardiacPhaseTime: ["(60_000 / values[0]) * (values[1] / 100)", "60_000 / values[0]"],
  visualAngle: ["2 * atan(values[0] / (2 * values[1])) * 180 / .pi", "atan(values[0] / (2 * values[1])) * 180 / .pi"],
  serialAbsorption: ["100 - (100 - values[0]) * ((100 - values[1]) / 100)", "(100 - values[0]) * ((100 - values[1]) / 100)"],
  hormoneSignal: ["100 * pow(2, -values[1] / values[0])", "100 - 100 * pow(2, -values[1] / values[0])"],
  immuneComposition: ["values[0] * values[1] / 100", "values[0] - values[0] * values[1] / 100"],
  ductTransit: ["values[0] / values[1]", "1 / values[1]"],
  oviductCiliaryCycles: ["values[0] * values[1]", "1000 / values[0]"],
  kneeMoment: ["values[0] * (values[1] / 100)", "values[1] / 100"]
} : {
  capillaryExchange: ["-100 * expm1(-values[0] / values[1])", "100 * exp(-values[0] / values[1])"],
  valveFlux: ["values[0] * values[1]", "(values[0] * values[1]) * 0.1"],
  glomerularFiltration: ["max(0, values[0] - values[1] - values[2]) * values[3]", "values[0] - values[1] - values[2]"],
  skinWaterBarrier: ["values[0] * values[1] / values[2]", "values[0] / values[2]"],
  salivaryDelivery: ["values.reduce(0, +)", "values.reduce(0, +) * 5"],
  tendonElongation: ["values[1] * (values[0] / (values[3] * values[2]))", "100 * (values[0] / (values[3] * values[2]))"],
  airwaySplit: ["values[0] * values[2] / (values[1] + values[2])", "values[0] * values[1] / (values[2] + values[1])"],
  peristalticTravel: ["values[0] * values[1]", "100 * (values[0] * values[1]) / 10"],
  cochlearFrequency: ["165.4 * (pow(10, 2.1 * values[0]) - 0.88)", "100 * (1 - values[0])"]
};
for (const [id, pair] of Object.entries(formulas)) for (const [index, expression] of pair.entries()) {
  const method = index === 0 ? values.split("func evaluate")[1].split("func companion")[0] : values.split("func companion")[1];
  assert(normalize(method).includes(normalize("case ." + id + ": result = " + expression)), id);
}
if (system) for (const suffix of ["diaphragm_demo_diagram", "diaphragm_demo_current", "diaphragm_demo_resting",
  "teaching_unit_cells", "teaching_unit_cycles", "teaching_unit_heart_rate"]) resourceKeys.add("health_atlas_" + suffix);
if (organ) for (const suffix of ["diagram", "section", "speed"]) resourceKeys.add("health_atlas_arterial_continuity_" + suffix);
if (regional) for (const suffix of ["bladder_expansion_caption", "bladder_expansion_description", "bladder_expansion_before",
  "bladder_expansion_current", "bladder_expansion_play", "bladder_expansion_pause", "airway_ciliary_clearance_diagram",
  "airway_ciliary_clearance_track"]) resourceKeys.add("health_atlas_" + suffix);
if (transport) {
  for (const suffix of ["caption", "counter", "diagram", "play", "pause", "pelvis", "tube", "bladder"])
    resourceKeys.add("health_atlas_ureter_delivery_" + suffix);
  for (const suffix of ["diagram", "incident_ray", "refracted_ray", "surface"])
    resourceKeys.add("health_atlas_model_corneal_refraction_" + suffix);
}
assert.equal(resourceKeys.size, transport ? 66 : regional ? 62 : organ ? 57 : 60);
for (const locale of ["en", "zh-Hans"]) {
  const table = new Map([...read("GalaxySSI/" + locale + ".lproj/" + (transport ? "AtlasTransportTeaching" : regional ? "AtlasRegionalTeaching" : organ ? "AtlasOrganTeaching" : system ? "AtlasSystemTeaching" : "AtlasTeaching") + ".strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]));
  assert.deepEqual(new Set(table.keys()), resourceKeys); for (const value of table.values()) assert(value);
}
for (const token of ["-100 * expm1(-values[0] / values[1])", "100 * exp(-values[0] / values[1])", "max(0, values[0] - values[1] - values[2]) * values[3]",
  "values[0] * values[2] / (values[1] + values[2])", "values[0] * values[1] / (values[2] + values[1])", "165.4 * (pow(10, 2.1 * values[0]) - 0.88)",
  "100 * (1 - values[0])", "values[1] * (values[0] / (values[3] * values[2]))", "guard accepts(values)", "input.scale > 0"])
  assert(values.includes(token), token);
const previous = git(["show", "6fe78ae14dc434edfb1b23a6f04d62bbd679f5f3:apps/ios/GalaxySSI/GalaxySSIHealthAtlasPhysiology.swift"]).toString();
const routing = text => text.split("static func forEntry(_ id: String)")[1].split("default:")[0];
assert.equal(routing(physiology), routing(previous), "Existing model routes must keep precedence");
const oldOwners = [...routing(previous).matchAll(/"([a-z0-9-]+)"/g)].map(m => m[1]);
assert.equal(new Set(oldOwners).size, 67); assert(owners.every(id => !oldOwners.includes(id)));
for (const token of ["teaching!.inputs", "teaching!.sources[0]", "kind.teaching!.evaluate(values)", "kind.teaching!.companion(inputs.indices.map(input))",
  "default: return GalaxySSIHealthAtlasTeachingModel.forEntry(id)"]) assert(physiology.includes(token), token);
assert(source("PhysiologyText").includes("GalaxySSIHealthAtlasTeachingModel.resource(key)"));
assert(source("PhysiologyPanel").includes('"atlas-physiology-curve"'));
for (const token of ['"atlas-physiology-output"', '"atlas-physiology-companion"', '"atlas-physiology-reset"', '"atlas-physiology-" + spec.key'])
  assert(source("PhysiologyPanel").includes(token));
const state = source("State");
assert(state.includes("entries[entry.id]")); assert(state.includes("Physiology.restore(id, inputs: entries[id]?.physiologyInputs)"));
assert(source("PhysiologyText").includes("kind.teaching?.digits ?? 2"));
if (system) {
  const archived = JSON.parse(read("ANDROID_4397_MODEL_DECLARATIONS.json")).models;
  assert(owners.every(id => !archived.some(m => m.entryIDs.includes(id))), "Do not replace preceding teaching routes");
  for (const token of ['case .diaphragmDisplacement: art.diaphragm(model)', '"atlas-diaphragm-displacement"',
    '"health_atlas_diaphragm_demo_diagram"']) assert(source("MaterialResponseView").includes(token));
  for (const token of ["108 * sqrt(model.input(1) / 250)", "model.input(0) * 1.1", "dash: [6, 4]",
    "0xDEEEEF", "0xA7D7C9", 'label("diaphragm_demo_current", 261, 147, 98)',
    'label("diaphragm_demo_resting", 111, 147, 98)']) assert(source("MaterialResponseDrawing").includes(token));
  assert(source("PhysiologyText").includes('displayUnit(model.kind.unit, language: language)'));
  assert(source("PhysiologyText").includes('displayUnit(spec.unit, language: language)'));
  assert.equal((source("PhysiologyPanel").match(/PhysiologyText.displayUnit/g) || []).length, 3);
  assert(source("").includes('table: "AtlasSystemTeaching"'));
}
if (organ) {
  for (const revision of [4397, 4399]) {
    const archived = JSON.parse(read(`ANDROID_${revision}_MODEL_DECLARATIONS.json`)).models;
    assert(owners.every(id => !archived.some(m => m.entryIDs.includes(id))), "Do not replace preceding teaching routes");
  }
  for (const token of ['case .arterialContinuity: art.arterialContinuity(model)', '"atlas-arterial-continuity"',
    '"health_atlas_arterial_continuity_diagram"']) assert(source("MaterialResponseView").includes(token));
  for (const token of ["model.input(0) * 1.15", "model.result / model.kind.bounds.upperBound", "0xBA8290", "0xEFC8CB",
    "max(8, (end - start) * speed)", 'label("arterial_continuity_section", x, 145, 134)',
    'label("arterial_continuity_speed", (start + end) / 2, 145, 172)']) assert(source("MaterialResponseDrawing").includes(token));
  assert(source("").includes('table: "AtlasOrganTeaching"'));
}
if (regional) {
  for (const revision of [4397, 4399, 4401]) {
    const archived = JSON.parse(read(`ANDROID_${revision}_MODEL_DECLARATIONS.json`)).models;
    assert(owners.every(id => !archived.some(m => m.entryIDs.includes(id))));
  }
  for (const token of ['case .airwayCiliaryClearance: art.ciliaTrack(model)', '"atlas-airway-cilia-track"',
    '"health_atlas_airway_ciliary_clearance_diagram"']) assert(source("MaterialResponseView").includes(token));
  for (const token of ["model.companionValue / 100", "for i in 0..<9", "for branch in 0..<4", "addQuadCurve",
    "0xD3E8E3", "0xA4D4CB", "0xBC803F", 'label("airway_ciliary_clearance_track", 170, 145, 300)'])
    assert(source("MaterialResponseDrawing").includes(token));
  const sharedPlayer = fs.existsSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlasTeachingPlayback.swift"));
  const player = sharedPlayer ? source("TeachingPlayback") : source("BladderFillingView");
  for (const token of ["TimelineView(.animation", "if offset >= 1 { offset = 0 }", 'onChange(of: resetToken)',
    'onChange(of: reduceMotion)', 'onChange(of: scenePhase)', 'onDisappear { pause() }']) assert(player.includes(token));
  assert(player.includes(sharedPlayer ? 'date.timeIntervalSince($0) / duration' : 'date.timeIntervalSince(startedAt) / 1.8'));
  assert(player.includes(sharedPlayer ? 'onChange(of: modelKey)' : 'onChange(of: model)'));
  if (sharedPlayer) assert(source("BladderFillingView").includes('duration: model.input(1) > 0 ? 1.8 : 0'));
  for (const token of ['"atlas-bladder-filling-play"', '"atlas-bladder-filling-diagram"',
    "cbrt(volume / 450)", "61 * relativeRadius", "102 - 92 * relativeRadius", "0xFFE8B3", "0xD5A26C"])
    assert(source("BladderFillingView").includes(token));
  assert(source("PhysiologyPanel").includes('resetToken: resetToken).id(entryID)'));
  assert(source("").includes('table: "AtlasRegionalTeaching"'));
}
if (transport) {
  for (const revision of [4397, 4399, 4401, 4402]) {
    const archived = JSON.parse(read(`ANDROID_${revision}_MODEL_DECLARATIONS.json`)).models;
    assert(owners.every(id => !archived.some(m => m.entryIDs.includes(id))));
  }
  for (const token of ['case .cornealRefraction: art.refraction(model)', '"atlas-corneal-rays"',
    '"health_atlas_model_corneal_refraction_diagram"']) assert(source("MaterialResponseView").includes(token));
  for (const token of ["sin(incident)", "cos(refracted)", "dash: [4, 4]", "baseX - 3.5 * dy", "radius: 25",
    'label("model_corneal_refraction_surface", 253, 65, 128)']) assert(source("MaterialResponseDrawing").includes(token));
  for (const token of ['duration: 1.1 * Double(model.inputs[0])', 'modelKey: model.inputs, resetToken: resetToken',
    '"atlas-ureter-transport-play"', '"atlas-ureter-transport-diagram"', 'sqrt(packetVolume / 3)',
    'frame.inTransit.map { $0 - 0.075 }', 'for index in 0...52', '82 - 27 * sin(.pi * at)',
    '10 - 7 * exp(-fromWave * fromWave)', 'for i in 0..<6', 'position - Double(whole)'])
    assert(source("UreterTransportView").includes(token));
  const player = source("TeachingPlayback");
  for (const token of ['TimelineView(.animation', 'duration.isFinite && duration > 0', 'onChange(of: modelKey)',
    'onChange(of: resetToken)', 'onChange(of: scenePhase)', 'onChange(of: reduceMotion)', 'onDisappear { pause() }']) assert(player.includes(token));
  assert(source("BladderFillingView").includes('GalaxySSIHealthAtlasTeachingPlayback('));
  assert(source("PhysiologyPanel").includes('GalaxySSIHealthAtlasUreterTransportView(model: model, language: language, resetToken: resetToken).id(entryID)'));
  for (const token of ['"gut-section-" + id', 'section.selectorLabel = section.viewLabel',
    '!views.contains(where: { $0.asset == section.asset })', 'return views + [section]', 'table: "AtlasTransportTeaching"']) assert(source("").includes(token));
}
console.log(`Android #${revision} source: ${changed.length} hashes, nine declarations / ${controls.length} controls / ${owners.length} new owners / ${resourceKeys.size} bilingual keys; existing 67 route clauses unchanged. Not Swift execution or native acceptance.`);
