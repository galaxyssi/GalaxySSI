import SwiftUI
import UIKit

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func acinarGranule(_ x: Double, _ y: Double, _ r: Double) {
    disc(x, y, r, 0xEEB17E, border: 0x9C693D)
    disc(x - r * 0.17, y - r * 0.23, r * 0.35, 0xF8D6A6)
  }
  func acinarCargo(_ x: Double, _ y: Double, precursor: Bool, radius: Double) {
    if precursor {
      acinarFilled(GalaxySSIHealthAtlasAcinarGeometry.diamond(x, y, radius), fill: 0x644474, edge: Self.cream)
    } else {
      disc(x, y, radius, 0x9D4839, border: Self.cream)
    }
  }
  func acinarCargoKeys() {
    acinarCargoKey("acinar_enzyme_story_enzymes", center: 91, precursor: false)
    acinarCargoKey("acinar_enzyme_story_precursors", center: 259, precursor: true)
  }
  private func acinarCargoKey(_ key: String, center: Double, precursor: Bool) {
    let text = GalaxySSIHealthAtlasFunctionText.get("health_atlas_" + key, language)
    let width = min(126, Double((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width))
    acinarCargo(center - width / 2 - 3, 321, precursor: precursor, radius: 4.3)
    label(key, center + 8, 325, 126)
  }
  func acinarFluidMark(_ x: Double, _ y: Double) {
    line(x - 4, y + 1, x + 1, y - 1, 0x276F75, 1.7)
    line(x, y + 3, x + 5, y + 1, 0x276F75, 1.5)
  }
  func acinarTube(_ path: Path, _ outer: Double, _ inner: Double) {
    stroke(path, 0x517C7A, outer); stroke(path, 0xD7EFEA, inner)
  }
  func acinarFilled(_ path: Path, fill: UInt32, edge: UInt32) {
    self.fill(path, fill); stroke(path, edge, 1.2)
  }
  func acinarFilled(_ path: Path, top: Double, bottom: Double, from: UInt32, to: UInt32, edge: UInt32) {
    gradient(path, top, bottom, from, to); stroke(path, edge, 1.2)
  }
}
