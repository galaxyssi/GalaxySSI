// Restricted constant-path grammar; fails closed instead of evaluating arbitrary Kotlin.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663", check = process.argv.includes("--check");
for (const [sourceName, nativeName, count, routeNames] of [["ThyroidCalcitonin", "Calcitonin", 6, ["capillary"]], ["AdrenalCortex", "AdrenalCortex", 2, ["section", "sinusoid"]]]) {
  const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + sourceName + "StoryView.kt"], {cwd: root, encoding: "utf8"});
  const declarations = [...source.matchAll(/private val (\w+) = curve \{([^}]+)\}/g)];
  assert.equal(declarations.length, count);
  let text = "import SwiftUI\n\n// Generated from pinned Android #4388 constant curve declarations.\nenum GalaxySSIHealthAtlas" + nativeName + "Geometry {\n", commands = 0;
  const arity = {moveTo: 2, lineTo: 2, quadTo: 4, cubicTo: 6, close: 0};
  for (const [, name, body] of declarations) {
    const calls = [...body.matchAll(/(moveTo|lineTo|quadTo|cubicTo|close)\(([^)]*)\)/g)];
    assert.equal(body.replace(/(moveTo|lineTo|quadTo|cubicTo|close)\([^)]*\)/g, "").trim(), "", name);
    let start, end, route = [];
    text += "  static let " + name + " = Path { p in\n";
    for (const [, op, args] of calls) {
      const tokens = args.trim() ? args.split(",").map(s => s.trim()) : [];
      assert.equal(tokens.length, arity[op]); assert.ok(tokens.every(s => /^-?(?:\d+(?:\.\d*)?|\.\d+)f$/.test(s)), name);
      const a = tokens.map(s => Number(s.slice(0, -1))), point = i => ".init(x: " + a[i] + ", y: " + a[i + 1] + ")";
      if (op === "moveTo") { assert.equal(start, undefined); start = a; end = a; }
      else if (op !== "close") { assert.ok(start); end = a.slice(-2); route.push(".init(kind: ." + ({lineTo: "line", quadTo: "quad", cubicTo: "cubic"}[op]) + ", points: [" + a.filter((_, i) => i % 2 === 0).map((_, i) => point(i * 2)).join(", ") + "])"); }
      else if (routeNames.includes(name)) assert.deepEqual(end, start, "Closed sampling route needs explicit closing segment");
      const line = op === "moveTo" ? "p.move(to: " + point(0) + ")" : op === "lineTo" ? "p.addLine(to: " + point(0) + ")" :
        op === "quadTo" ? "p.addQuadCurve(to: " + point(2) + ", control: " + point(0) + ")" :
        op === "cubicTo" ? "p.addCurve(to: " + point(4) + ", control1: " + point(0) + ", control2: " + point(2) + ")" : "p.closeSubpath()";
      text += "    " + line + "\n"; commands++;
    }
    text += "  }\n";
    if (routeNames.includes(name)) text += "  static let " + name + "Route = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: " + start[0] + ", y: " + start[1] + "), commands: [\n    " + route.join(",\n    ") + "])\n";
  }
  text += "}\n";
  const file = path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + nativeName + "Geometry.swift");
  if (check) assert.equal(fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n"), text); else fs.writeFileSync(file, text);
  console.log(nativeName + ": " + count + " source paths / " + commands + " commands. No native execution.");
}
