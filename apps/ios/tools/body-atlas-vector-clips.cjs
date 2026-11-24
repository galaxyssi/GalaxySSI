const {PDFOperator, PDFNumber} = require("pdf-lib");
const {svgPathToOperators} = require("pdf-lib/cjs/api/svgPath.js");
const normalize = require("./body-atlas-quadratic-path.cjs");

// Clip geometry is expressed in page coordinates so it cannot alter the later path CTM.
module.exports = function clipOperators(clip, height) {
  const geometry = svgPathToOperators(normalize(clip.pathData)).map(op => {
    if (!["m", "l", "c", "h"].includes(op.name)) throw Error("Unsupported normalized clip operation");
    return PDFOperator.of(op.name, op.args.map((n, i) => PDFNumber.of(i % 2 ? height - n.asNumber() : n.asNumber())));
  });
  return [...geometry, PDFOperator.of(clip.evenOdd ? "W*" : "W"), PDFOperator.of("n")];
};
