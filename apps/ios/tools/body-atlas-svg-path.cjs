const svgpath = require("./vendor/svgpath-2.6.0");

module.exports = function normalizedSVGPath(data) {
  const path = svgpath(data);
  if (path.err) throw Error("Invalid atlas SVG path: " + path.err);
  return path.abs().unshort().unarc().toString();
};
