import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private func acinarCellPlate(fused: Bool = false) {
    typealias Geometry = GalaxySSIHealthAtlasAcinarGeometry
    acinarFilled(Geometry.facingCell, fill: 0xEDB9A7, edge: 0x995E66)
    oval(299, 153, 321, 181, fill: 0xB886A6, border: 0x765780)
    for i in 0...3 { disc(282 + Double(i % 2) * 7, 152 + Double(i) * 13, 3.2, 0xEEB17E, border: 0x9C693D) }
    acinarFilled(Geometry.acinarSpace, fill: 0xD7EFEA, edge: 0x517C7A)
    gradient(Geometry.cell, 88, 256, 0xFDE4CE, 0xDF9FA4)
    stroke(Geometry.cellOuterMembrane, 0x995E66, 1.65)
    if fused {
      fill(Geometry.fusionMouth, 0xD7EFEA); stroke(Geometry.fusionMouth, 0x995E66, 1.85)
      line(240, 136, 240, 169, 0x995E66, 1.85)
      line(240, 181, 240, 204, 0x995E66, 1.85)
    } else {
      line(240, 136, 240, 204, 0x995E66, 1.85)
    }
    oval(53, 177, 107, 224, fill: 0xC497B3, border: 0x765780)
    oval(74, 191, 88, 205, fill: 0xB886A6, border: 0x765780)
    for (row, fold) in Geometry.erFolds.enumerated() {
      stroke(fold, 0xE2BAD2, 4.5); stroke(fold, 0x765780, 1.1)
      for i in 0...4 { disc(65 + Double(i) * 9, 117 + Double(row) * 8 + (i < 2 ? 0 : 1.6), 0.9, 0x765780) }
    }
    for stack in Geometry.golgiStacks { stroke(stack, 0xF1C499, 3.8); stroke(stack, 0xAB7054, 1.15) }
    acinarGranule(191, 144, 6); acinarGranule(208, 151, 7); acinarGranule(226, 148, 5.5)
    acinarGranule(199, 192, 6); acinarGranule(216, 195, 7); acinarGranule(228, 193, 4.4)
  }
  func acinarPackageCargo(_ t: Double) {
    typealias Motion = GalaxySSIHealthAtlasAcinarMotion
    typealias Routes = GalaxySSIHealthAtlasAcinarRoutes
    acinarCellPlate()
    let early = Motion.synthesize(t), late = Motion.store(t)
    if early < 1 {
      at(Routes.toGolgi, early) { x, y in acinarGranule(x, y, 3.5) }
      at(Routes.toGolgi, max(0, early - 0.23)) { x, y in disc(x, y + 6, 2.3, 0x9D4839, border: Self.cream) }
    }
    if late > 0 { at(Routes.toStorage, late) { x, y in acinarGranule(x, y, 3.5 + late * 4) } }
  }
  func acinarReleaseCargo(_ t: Double) {
    typealias Motion = GalaxySSIHealthAtlasAcinarMotion
    let dock = Motion.dock(t), release = Motion.release(t)
    acinarCellPlate(fused: dock >= 1)
    if dock < 1 {
      acinarGranule(Motion.mix(201, 232, dock), Motion.mix(168, 175, dock), 8)
    } else {
      for i in 0...3 {
        let p = release * 1.14 - 0.14 * Double(i)
        if (0...1).contains(p) {
          at(GalaxySSIHealthAtlasAcinarRoutes.outOfCell, p) { x, y in
            acinarCargo(x, y + Double(i % 2) * 4 - 2, precursor: i % 2 == 1, radius: 2.8)
          }
        }
      }
    }
    acinarCargoKeys()
  }
}
