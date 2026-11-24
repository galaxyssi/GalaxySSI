# svgpath Tooling Dependency

- Package: `svgpath@2.6.0`
- Source: https://github.com/fontello/svgpath
- Official registry: https://registry.npmjs.org/svgpath
- License: MIT; original `LICENSE` is included unchanged.
- Registry archive integrity:
  `sha512-OIWR6bKzXvdXYyO4DK/UWa1VA1JeKq8E+0ug2DG98Y/vOmMpfZNj+TIG988HjfYSqtcy/hFOtZq/n/j5GSESNg==`
- All eleven files in the published distribution are retained unchanged under
  `svgpath-2.6.0`. The downloaded archive hash was checked against the official
  npm registry metadata. No package scripts were executed.

Used only by iOS asset-conversion/source-check tooling, not linked into the app.
It resolves relative commands and reflected smooth-curve controls before PDF
encoding. This avoids the existing PDF parser's consecutive-T reflection issue
and lets quadratic-to-cubic conversion preserve the original SVG geometry.
