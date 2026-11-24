const {svgPathToOperators} = require("pdf-lib/cjs/api/svgPath.js");

// pdf-lib emits SVG Q/T controls as four-operand PDF v operations. Convert them
// to equivalent cubics before PDF drawing so the original quadratic is retained.
module.exports = function quadraticPath(data) {
  let x = 0, y = 0, startX = 0, startY = 0;
  return svgPathToOperators(require("./body-atlas-svg-path.cjs")(data)).map(op => {
    const a = op.args.map(n => n.asNumber());
    if (!a.every(Number.isFinite)) throw Error("Nonfinite SVG coordinates");
    switch (op.name) {
      case "m": [x, y] = a; startX = x; startY = y; return "M" + a.join(" ");
      case "l": [x, y] = a; return "L" + a.join(" ");
      case "c": x = a[4]; y = a[5]; return "C" + a.join(" ");
      case "v": {
        const [cx, cy, endX, endY] = a;
        const cubic = [x + (cx - x) * 2 / 3, y + (cy - y) * 2 / 3,
          endX + (cx - endX) * 2 / 3, endY + (cy - endY) * 2 / 3, endX, endY];
        x = endX; y = endY;
        return "C" + cubic.join(" ");
      }
      case "h": x = startX; y = startY; return "Z";
      default: throw Error("Unsupported SVG operation " + op.name);
    }
  }).join(" ");
};
