// Mechanical conversion of pinned Android SVG path declarations into native Swift paths.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const {svgPathToOperators} = require("pdf-lib/cjs/api/svgPath.js");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const check = process.argv.includes("--check");
for (const [android, native, expected] of [["SkullProtection", "Skull", 16], ["VertebralMotion", "Vertebral", 11]]) {
  const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + android + "StoryView.kt"], {cwd: root, encoding: "utf8"});
  const declarations = [...source.matchAll(/private val (\w+) = path\("([^"]+)"\)/g)];
  if (declarations.length !== expected) throw Error("Source path inventory changed: " + android);
  let text = "import SwiftUI\n\n// Exact Android #4385 SVG coordinates, including relative and reflected quadratic controls.\nenum GalaxySSIHealthAtlas" + native + "Geometry {\n";
  let commands = 0;
  for (const [, name, data] of declarations) {
    text += "  static let " + name + " = Path { p in\n";
    for (const op of svgPathToOperators(require("./body-atlas-svg-path.cjs")(data))) {
      const a = op.args.map(n => n.asNumber());
      if (!a.every(Number.isFinite)) throw Error("Nonfinite path coordinates");
      const point = i => "CGPoint(x: " + a[i] + ", y: " + a[i + 1] + ")";
      const line = op.name === "m" ? "p.move(to: " + point(0) + ")" :
        op.name === "l" ? "p.addLine(to: " + point(0) + ")" :
        op.name === "c" ? "p.addCurve(to: " + point(4) + ", control1: " + point(0) + ", control2: " + point(2) + ")" :
        // svgPathToOperators preserves Q/T controls in its four-operand v operator.
        op.name === "v" ? "p.addQuadCurve(to: " + point(2) + ", control: " + point(0) + ")" :
        op.name === "h" ? "p.closeSubpath()" : null;
      if (!line) throw Error("Unsupported source path operation " + op.name);
      text += "    " + line + "\n"; commands++;
    }
    text += "  }\n";
  }
  text += "}\n";
  const destination = path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + native + "Geometry.swift");
  if (check) {
    if (fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n") !== text) throw Error("Axial geometry drift: " + native);
  } else fs.writeFileSync(destination, text);
  console.log(native + ": " + expected + " original SVG paths / " + commands + " native path commands. No Swift/native execution.");
}
