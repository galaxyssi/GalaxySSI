// Evaluate only original pure path declarations with recording Path DTOs.
// Android renderers, native Swift, Xcode and XCTest are not built or executed.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), os = require("node:os");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc", check = process.argv.includes("--check");
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasUterocervicalStoryView.kt"], {cwd: root, encoding: "utf8"});
const start = source.indexOf("    // The same schematic"), end = source.indexOf("    override fun scene", start);
if (start < 0 || end < start) throw Error("Uterocervical geometry boundaries changed");
const declarations = source.slice(start, end), names = [...declarations.matchAll(/private val (\w+) =/g)].map(m => m[1]);
const keys = [...new Set([...declarations.matchAll(/string\.(\w+)/g)].map(m => m[1]))];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-uterocervical-")), files = [];
function generated(name, text) { const file = path.join(temp, name + ".kt"); fs.writeFileSync(file, text); files.push(file); }
generated("Geometry", `package com.galaxyssi.chat
import com.galaxyssi.chat.R.string
internal object Geometry {
${declarations}
    private fun track(path: Path) = path
    private inline fun shape(block: Path.() -> Unit) = Path().apply(block)
}
internal object R { object string {
${keys.map((k, i) => "const val " + k + " = " + i).join("\n")}
}}
`);
generated("RecordingPath", `package com.galaxyssi.chat
internal class Path {
    val commands = mutableListOf<Map<String, Any>>()
    private var x = 0f; private var y = 0f; private var sx = 0f; private var sy = 0f
    private fun record(kind: String, vararg values: Float) {
        commands.add(mapOf("kind" to kind, "values" to values.map { it.toDouble() }))
        if (values.isNotEmpty()) { x = values[values.size - 2]; y = values.last() }
    }
    fun moveTo(a: Float, b: Float) { record("move", a, b); sx = a; sy = b }
    fun lineTo(a: Float, b: Float) = record("line", a, b)
    fun quadTo(a: Float, b: Float, c: Float, d: Float) = record("quad", a, b, c, d)
    fun cubicTo(a: Float, b: Float, c: Float, d: Float, e: Float, f: Float) = record("cubic", a, b, c, d, e, f)
    fun rQuadTo(a: Float, b: Float, c: Float, d: Float) = quadTo(x + a, y + b, x + c, y + d)
    fun close() { record("close"); x = sx; y = sy }
}
`);
let exporter = fs.readFileSync(path.join(__dirname, "AtlasFunctionStructuresExport.kt"), "utf8");
exporter = exporter.slice(0, exporter.indexOf("private fun marker"));
exporter = exporter.replace(/^private fun key\(id: Int\) = ResourceNames.keys\[id - 1\]\r?\n/m, "");
generated("Export", exporter + `
fun main() {
    val names = listOf(${names.map(n => JSON.stringify(n)).join(",")})
    val values = names.mapNotNull { name ->
        val value = Geometry::class.java.getDeclaredField(name).apply { isAccessible = true }.get(Geometry)
        when (value) {
            is Path -> mapOf("name" to name, "paths" to listOf(value.commands))
            is List<*> -> {
                require(value.all { it is Path })
                mapOf("name" to name, "paths" to value.map { (it as Path).commands })
            }
            else -> null
        }
    }
    println(json(values))
}
`);
const data = require("./atlas-kotlin-extract.cjs")({files, temporary: temp, mainClass: "com.galaxyssi.chat.ExportKt", cwd: root});
const groups = {Locator: ["locatorVagina", "locatorVaginalSpace", "locatorCervix", "locatorUterus", "locatorCavity", "locatorCanal", "locatorTraces", "locatorOs", "locatorWallTexture"],
  Wall: ["wallSurface", "wallMuscle", "wallLining", "wallFibers", "wallGlands", "wallRims"],
  Canal: ["upperVagina", "neck", "canalSpace", "neckCollagen", "canalFolds", "neckTrace"],
  Vaginal: ["deepVaginalWall", "muscleVaginalWall", "facingVaginalWall", "vaginalMuscleFibers"]};
if (data.length !== Object.values(groups).flat().length || data.some(d => !Object.values(groups).flat().includes(d.name))) throw Error("Source geometry inventory mismatch");
function nativePath(commands, indent) {
  const point = (v, i) => "CGPoint(x: " + v[i] + ", y: " + v[i + 1] + ")";
  return "Path { p in\n" + commands.map(c => {
    const v = c.values;
    const line = c.kind === "move" ? "p.move(to: " + point(v, 0) + ")" : c.kind === "line" ? "p.addLine(to: " + point(v, 0) + ")" :
      c.kind === "quad" ? "p.addQuadCurve(to: " + point(v, 2) + ", control: " + point(v, 0) + ")" :
      c.kind === "cubic" ? "p.addCurve(to: " + point(v, 4) + ", control1: " + point(v, 0) + ", control2: " + point(v, 2) + ")" : c.kind === "close" ? "p.closeSubpath()" : null;
    if (!line) throw Error("Unknown recorded path command"); return indent + "  " + line;
  }).join("\n") + "\n" + indent + "}";
}
let paths = 0, commands = 0;
for (const [group, members] of Object.entries(groups)) {
  let text = "import SwiftUI\n\n// Android #4385 declarations evaluated with original Float arithmetic and relative controls.\nenum GalaxySSIHealthAtlasUterocervical" + group + "Geometry {\n";
  for (const name of members) {
    const value = data.find(d => d.name === name); paths += value.paths.length; commands += value.paths.reduce((n, p) => n + p.length, 0);
    const list = ["locatorTraces", "wallRims"].includes(name);
    text += "  static let " + name + (list ? ": [Path] = [\n" + value.paths.map(p => "    " + nativePath(p, "    ")).join(",\n") + "\n  ]\n" : " = " + nativePath(value.paths[0], "  ") + "\n");
    if (name === "locatorTraces" || name === "neckTrace") {
      const tracks = value.paths.map(p => {
        if (p[0].kind !== "move" || p.slice(1).some(c => !["line", "quad", "cubic"].includes(c.kind))) throw Error("Noncontinuous teaching trace");
        return "GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: " + p[0].values[0] + ", y: " + p[0].values[1] + "), commands: [\n" + p.slice(1).map(c => "      .init(kind: ." + c.kind + ", points: [" + Array.from({length: c.values.length / 2}, (_, i) => ".init(x: " + c.values[2 * i] + ", y: " + c.values[2 * i + 1] + ")").join(", ") + "]),").join("\n") + "\n    ]))";
      });
      text += "  static let " + (list ? "tracks = [\n    " + tracks.join(",\n    ") + "\n  ]" : "track = " + tracks[0]) + "\n";
    }
  }
  text += "}\n";
  const destination = path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlasUterocervical" + group + "Geometry.swift");
  if (check) { if (fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n") !== text) throw Error("Uterocervical geometry drift " + group); }
  else fs.writeFileSync(destination, text);
}
console.log((check ? "Verified " : "Extracted ") + paths + " original uterocervical paths / " + commands + " commands, static loop/relative controls and four continuous trace DTOs. No Android scene or native execution.");
