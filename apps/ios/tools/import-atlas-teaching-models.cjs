// Evaluate original pure production declarations only; no Android UI, tests or Swift compilation.
const fs = require("node:fs"), path = require("node:path"), os = require("node:os"), cp = require("node:child_process"), crypto = require("node:crypto"), assert = require("node:assert/strict");
const transport = process.argv.includes("--transport-4405"), regional = process.argv.includes("--regional-4402"), organ = process.argv.includes("--organ-4401"), system = process.argv.includes("--system-4399"), revision = transport ? 4405 : regional ? 4402 : organ ? 4401 : system ? 4399 : 4397;
const root = path.resolve(__dirname, "../../.."), sha = transport ? "82d853f1d3d9c7e3455e732771f876a911fd0ce7" : regional ? "0d0112b055947c3747c7910b255aa299587dfd75" : organ ? "e228e379f307fcd6c1eb93b289126e9c473ddf7e" : system ? "de05fd51ba151789acd24dc4484d7f84d893aea3" : "40776e7a67ebfe48c76f98d392849edb9810ac82", check = process.argv.includes("--check");
const directory = "apps/android/app/src/main/java/com/galaxyssi/chat/";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 32_000_000});
const names = transport ? ["UreterDelivery", "CornealRefraction", "ExternalEarResonance", "NeuralRelayDelays", "BiliaryFlowTally", "ParathyroidSignalOccupancy", "FollicleSurface", "JointArticularArc", "SweatDuctBalance"] : regional ? ["BladderExpansion", "VestibularTilt", "AirwayCiliaryClearance", "GastricLiquidEmptying", "BileStorage", "ThoracicCrossSection", "PlateletFragmentCount", "BoneRemodelingBalance", "CutaneousSebum"] : organ ? ["ArterialContinuity", "GlialCapacitance", "ColonicWaterBalance", "LymphParticleTransport", "EndocrineDilution", "BoneSection", "RetinalConvergence", "MuscleShortening", "KeratinGrowth"] : system ? ["Diaphragm", "CardiacPhaseTime", "VisualAngle", "SerialAbsorption", "HormoneSignal", "ImmuneComposition", "DuctTransit", "OviductCiliaryCycles", "KneeMoment"] : ["CapillaryExchange", "ValveFlux", "GlomerularFiltration", "SkinWaterBarrier", "SalivaryDelivery",
  "TendonElongation", "AirwaySplit", "PeristalticTravel", "CochlearFrequency"];
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-teaching-models-")), files = [];
function generated(name, text) {
  const target = path.join(temporary, name + ".kt"); fs.writeFileSync(target, text); files.push(target);
}
for (const name of ["TeachingModelSpec", ...names.map(n => n + "TeachingModel")]) {
  generated("HealthAtlas" + name, git(["show", sha + ":" + directory + "HealthAtlas" + name + ".kt"]).toString());
}
generated("Input", "package com.galaxyssi.chat\ninternal data class HealthAtlasInput(val key: String, val range: IntRange, val initial: Int, val scale: Double = 1.0)");
const keys = [...new Set(files.flatMap(file => [...fs.readFileSync(file, "utf8").matchAll(/R\.string\.(\w+)/g)].map(m => m[1])))].sort();
generated("R", "package com.galaxyssi.chat\ninternal object ResourceNames { val keys = arrayOf(" + keys.map(k => JSON.stringify(k)).join(",") + ") }\n" +
  "internal object R { object string {\n" + keys.map((k, i) => "const val " + k + " = " + (i + 1)).join("\n") + "\n}}\n");
generated("Export", String.raw`package com.galaxyssi.chat
private fun quote(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
  .map { c -> if (c.code > 127) "\\u" + c.code.toString(16).padStart(4, '0') else c.toString() }.joinToString("") + "\""
private fun json(v: Any?): String = when (v) {
  null -> "null"
  is String -> quote(v)
  is Number, is Boolean -> v.toString()
  is Map<*, *> -> v.entries.joinToString(",", "{", "}") { quote(it.key.toString()) + ":" + json(it.value) }
  is Iterable<*> -> v.joinToString(",", "[", "]") { json(it) }
  else -> error("Unsupported teaching declaration")
}
private fun key(id: Int) = ResourceNames.keys[id - 1]
fun main() {
  val models = listOf(MODELS).map { (id, spec) ->
    mapOf("id" to id, "inputs" to spec.inputs.map {
      mapOf("key" to it.control.key, "minimum" to it.control.range.first, "maximum" to it.control.range.last,
        "initial" to it.control.initial, "scale" to it.control.scale, "label" to key(it.label), "unit" to it.unit, "digits" to it.digits)
    }, "axis" to spec.axis, "unit" to spec.unit, "minimum" to spec.minimum, "maximum" to spec.maximum,
      "sources" to listOfNotNull(spec.source, spec.extraSource), "title" to key(spec.title), "scope" to key(spec.scope),
      "formula" to key(spec.formula), "companionTitle" to key(spec.companionTitle), "entryIDs" to spec.entryIds.toList(), "digits" to spec.digits)
  }
  println(json(models))
}
`.replace("MODELS", names.map(n => JSON.stringify(n === "Diaphragm" ? "diaphragmDisplacement" : n[0].toLowerCase() + n.slice(1)) + " to HealthAtlas" + n + "TeachingModel.spec").join(", ")));
const models = require("./atlas-kotlin-extract.cjs")({files, temporary, mainClass: "com.galaxyssi.chat.ExportKt", cwd: root});
assert.equal(models.length, 9); assert.equal(models.flatMap(m => m.inputs).length, transport || regional || organ || system ? 18 : 24);
const owners = models.flatMap(m => m.entryIDs); assert.equal(owners.length, transport ? 24 : regional ? 19 : organ ? 42 : system ? 35 : 34); assert.equal(new Set(owners).size, owners.length);
const source = {androidPR: revision, mergeCommit: sha};
function write(file, data) {
  const target = path.join(root, "apps/ios", file), text = JSON.stringify(data, null, 2) + "\n";
  if (check) assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
  else fs.writeFileSync(target, text);
}
write(`ANDROID_${revision}_MODEL_DECLARATIONS.json`, {schema: 1, source, models});
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
write(`ANDROID_${revision}_SOURCE_INVENTORY.json`, {schema: 1, source, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", (status === "D" ? sha + "^1" : sha) + ":" + file])).digest("hex")}))});
console.log(`${check ? "Verified" : "Exported"} nine original teaching specifications / ${models.flatMap(m => m.inputs).length} controls / ${owners.length} owners. No native execution or acceptance.`);
