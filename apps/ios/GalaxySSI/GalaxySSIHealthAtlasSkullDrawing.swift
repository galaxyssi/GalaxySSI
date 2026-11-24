import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let skullFluidRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 37, y: 153), commands: [
    .init(kind: .quad, points: [.init(x: 180, y: 70), .init(x: 323, y: 153)])
  ])
  func skullScene(_ step: Int, _ t: Double) {
    if step < 2 { skullTop(t, locate: step == 0) }
    else { skullSection(t, membranes: step == 3) }
  }
  private func skullTop(_ t: Double, locate: Bool) {
    let g = GalaxySSIHealthAtlasSkullGeometry.self
    skullWash(g.vault, 63, 302, 0xFFF6E6, 0xD4AD95, 0x8B7264)
    var clipped = context; clipped.clip(to: g.vault)
    copy(clipped).fill(g.frontal, 0x68FFF5D9); copy(clipped).fill(g.occipital, 0x78BE8F7D)
    stroke(g.vaultLight, 0x7AFFF9EC, 2.6)
    let sutures = [g.coronal, g.sagittal, g.lambdoid]
    for path in sutures { stroke(path, 0x876356, 1.55) }
    if locate {
      let y = 165 + t * 35
      let locator = Path { p in
        p.move(to: CGPoint(x: 95, y: y + 5))
        p.addQuadCurve(to: CGPoint(x: 265, y: y + 5), control: CGPoint(x: 180, y: y - 12))
      }
      context.stroke(locator, with: .color(Self.color(0x398295)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [4, 4]))
      skullCallout("vault_section", 69, 295, 114, 100, y + 4, 276)
    } else {
      let progress = t * Double(sutures.count)
      for (i, path) in sutures.enumerated() {
        let fraction = min(1, max(0, progress - Double(i)))
        if fraction > 0 {
          let trace = path.trimmedPath(from: 0, to: fraction)
          stroke(trace, 0x7FFAF1DA, 5); stroke(trace, 0x876356, 2.5)
        }
      }
      skullCallout("coronal", 66, 91, 120, 123, 130, 97)
      skullCallout("sagittal", 286, 182, 122, 180, 179, 187)
      skullCallout("lambdoid", 286, 292, 125, 215, 236, 275)
    }
    label("skull_protection_art_anterior", 180, 44, 134)
    label("skull_protection_art_posterior", 180, 328, 134)
  }
  private func skullSection(_ t: Double, membranes: Bool) {
    let g = GalaxySSIHealthAtlasSkullGeometry.self
    var local = context; local.translateBy(x: 0, y: 40)
    let art = copy(local)
    art.skullWash(g.fluid, 90, 181, 0xE0F4F2, 0xA9CFD8, 0x7AA9B4)
    art.skullWash(g.brain, 116, 242, 0xEFD1C6, 0xBB7F83, 0x8B6570)
    art.stroke(g.gyri, 0xB28086, 1.5); art.stroke(g.pia, 0x94606E, 2)
    art.skullWash(g.dura, 101, 148, 0xD4C5D6, 0xB0A0B7, 0x827C97)
    art.stroke(g.arachnoid, 0x5F7A93, 1.75)
    art.skullWash(g.tables, 64, 143, 0xFFF1D8, 0xDEC3A7, 0x8B7264)
    art.skullWash(g.diploe, 74, 133, 0xDAB38F, 0xC49477, 0xA9856E)
    var latticeContext = local; latticeContext.clip(to: g.diploe)
    copy(latticeContext).stroke(g.lattice, 0xF2D3AD, 1.6)
    if !membranes {
      latticeContext.opacity = Double(70 + Int(90 * t)) / 255
      copy(latticeContext).stroke(g.lattice, 0xFFEDC5, 2.8)
    }
    if membranes {
      var fluidContext = local; fluidContext.clip(to: g.fluid)
      var outsideBrain = Path(CGRect(x: 0, y: 0, width: 360, height: 360))
      outsideBrain.addPath(g.brain)
      fluidContext.clip(to: outsideBrain, style: FillStyle(eoFill: true))
      let fluidArt = copy(fluidContext)
      for i in 0...4 {
        let fraction = (t * 0.48 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
        fluidArt.at(Self.skullFluidRoute, fraction) { x, y in fluidArt.disc(x, y, 2, 0xBB398295) }
      }
    }
    if membranes {
      skullCallout("dura", 65, 66, 111, 64, 167, 72)
      skullCallout("arachnoid", 284, 66, 135, 279, 163, 72)
      skullCallout("pia", 65, 310, 110, 67, 195, 293)
      skullCallout("csf", 282, 310, 143, 288, 176, 293)
    } else {
      skullCallout("outer", 64, 65, 122, 100, 126, 72)
      skullCallout("diploe", 180, 65, 104, 180, 121, 72)
      skullCallout("inner", 296, 65, 122, 254, 145, 72)
      skullCallout("brain", 180, 310, 132, 180, 207, 293)
    }
  }
  private func skullCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tx: Double, _ ty: Double, _ startY: Double) {
    line(x, startY, tx, ty, 0x55717B, 1); disc(tx, ty, 2.35, 0xF7F7EC, border: 0x55717B)
    label("skull_protection_art_" + key, x, y, width)
  }
  private func skullWash(_ path: Path, _ top: Double, _ bottom: Double, _ first: UInt32, _ last: UInt32, _ edge: UInt32) {
    gradient(path, top, bottom, first, last); stroke(path, edge, 1.1)
  }
}
