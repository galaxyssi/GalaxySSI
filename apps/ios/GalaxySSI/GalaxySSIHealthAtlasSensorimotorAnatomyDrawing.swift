import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sensorimotorAnatomy() {
    typealias Geometry = GalaxySSIHealthAtlasSensorimotorGeometry
    sensorimotorArea(Geometry.hemisphere, 57, 205, 0xFFE6D9, 0xE3ADB5, Self.coral)
    fill(Geometry.premotor, 0xEBC99B); stroke(Geometry.premotor, 0xA3723C, 1.05)
    fill(Geometry.parietal, 0xBBD6BF); stroke(Geometry.parietal, 0x4D796A, 1.05)
    fill(Geometry.motor, 0xDB9A8E); stroke(Geometry.motor, 0x9B4945, 1.05)
    fill(Geometry.sensory, 0xB0CAD9); stroke(Geometry.sensory, 0x386C8B, 1.05)
    stroke(Geometry.folds, 0xB47F85, 1.15)
    stroke(Geometry.lateralSulcus, 0x8A5968, 1.65)
    stroke(Geometry.centralSulcus, 0x8A5968, 2)
  }
  func sensorimotorTarget() {
    typealias Geometry = GalaxySSIHealthAtlasSensorimotorGeometry
    line(261, 318, 345, 318, 0xBDC8B7, 1.2)
    rounded(206, 279, 231, 285, 2, 0xB7C4B6)
    stroke(Geometry.handle, 0x4D796A, 7); stroke(Geometry.handle, 0xCBDAC0, 4.5)
    sensorimotorArea(Geometry.cup, 262, 312, 0xE6EFDC, 0xAFC5A4, 0x4D796A)
    oval(273, 262, 318, 278, fill: 0xEFF2DC, border: 0x4D796A)
    oval(277, 265, 314, 275, fill: 0xC5D3B3, border: 0x8CA189)
  }
  func sensorimotorArea(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(path, top, bottom, from, to)
    stroke(path, border, 1.3)
  }
}
