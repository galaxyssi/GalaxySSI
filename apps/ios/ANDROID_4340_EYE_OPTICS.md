# iOS parity: Android #4340 eye structure and focus

Base: main. Android source: #4340, merge 24f22b76db1d7bb3764987ceb6354b16e1ab0679.

## Scope

- Convert all 16 original Android eye-section vector paths to a transparent
  vector-preserving iOS PDF asset. Retain the three localized cornea/lens/retina
  hotspot coordinates and prefer this plate over the sensory overview.
- Reuse existing layers, labels, fullscreen, zoom, shared captions and drilldown.
- Add bounded equivalent thin-lens optics for eye/lens only: object distance
  0.25-6 m, power 55-65 D in 0.01 D steps, signed offset from a fixed 17 mm plane,
  target power, a descending response curve and a native ray diagram.
- Add the retinal-plane focus action, independent per-entry input restoration,
  displayed-zero normalization and teaching-only public Agent context.
- Allow only the exact NIH NEI anatomy reference in addition to the existing
  OpenStax illustration sources; unrelated NIH URLs are not accepted.
- Import 14 English/Chinese strings per language and Android light/dark ray
  colors. Retain the source limitations: not acuity, diagnosis or prescription.

## Verification

- iOS structure, changed-source Swift grammar and whitespace checks passed.
- 28 localized strings match Android including placeholders and newlines.
- The generated PDF was rendered with Poppler and visually inspected; all
  eye-section paths are present. This is asset review, not a native screenshot.
- Added XCTest source for independent numeric fixtures, all object-distance
  steps, ray intersections, sign/precision, bounds, restoration, trusted source,
  plate routing and active/inactive public-context isolation. Not executed.
- No Xcode compile, native simulator/device validation or IPA is claimed.

Only iOS files are changed. This diff does not duplicate the aging-research
implementation from #4460.
