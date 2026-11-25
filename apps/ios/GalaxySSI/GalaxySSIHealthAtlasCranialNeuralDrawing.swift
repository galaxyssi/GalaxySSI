import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cranialNeural(_ frame: GalaxySSIHealthAtlasCranialMotion.Frame) {
    let sides = GalaxySSIHealthAtlasCranialRoutes.sides
    for side in sides {
      stroke(side.nerve.path, 0x8CB2A8, 2.8)
      stroke(side.stay.path, 0x8CB2A8, 2.1); stroke(side.cross.path, 0x8CB2A8, 2.1)
      stroke(side.localRelay.path, 0xAE94B7, 1.8); stroke(side.crossRelay.path, 0xAE94B7, 1.8)
      stroke(side.returnNerve.path, 0xC79BA1, 2.8); stroke(side.toIris.path, 0xC79BA1, 1.9)
    }
    for side in sides {
      cranialNode(side.x(154), 239, frame.pretectal, 0x26746E)
      cranialNode(side.x(148), 277, frame.pupilDrive, 0x755587)
      cranialNode(side.x(49), 153, frame.ganglionDrive, 0xA25264)
    }
    let t = frame.t
    switch frame.step {
    case 1:
      let side = sides[0], branch = (t - 0.42) / 0.53
      cranialSignal(side.nerve.route, side.nerve.path, t / 0.49, 0x26746E)
      cranialSignal(side.stay.route, side.stay.path, branch, 0x26746E)
      cranialSignal(side.cross.route, side.cross.path, branch, 0x26746E)
    case 2:
      for side in sides {
        let travel = (t - 0.10) / 0.77
        cranialSignal(side.localRelay.route, side.localRelay.path, travel, 0x755587)
        cranialSignal(side.crossRelay.route, side.crossRelay.path, travel, 0x755587)
      }
    case 3:
      for side in sides {
        cranialSignal(side.returnNerve.route, side.returnNerve.path, (t - 0.04) / 0.54, 0xA25264)
        cranialSignal(side.toIris.route, side.toIris.path, (t - 0.58) / 0.36, 0xA25264)
      }
    default: break
    }
  }
  func cranialNode(_ x: Double, _ y: Double, _ activity: Double, _ color: UInt32) {
    if activity > 0 {
      var glow = context; glow.opacity = Double(Int(110 * activity)) / 255
      let r = 6 + 4 * activity
      copy(glow).stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), color, 1.15)
    }
    disc(x, y, 3.6, activity > 0.3 ? color : Self.cream, border: color)
    if activity > 0.3 { disc(x, y, 1.35, Self.cream) }
  }
  func cranialSignal(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ path: Path, _ t: Double, _ color: UInt32) {
    guard t.isFinite, (0...1).contains(t) else { return }
    stroke(path.trimmedPath(from: max(0, t - 0.25), to: t), color, 3.1)
    at(route, t) { x, y in disc(x, y, 3.1, Self.cream, border: color) }
  }
}
