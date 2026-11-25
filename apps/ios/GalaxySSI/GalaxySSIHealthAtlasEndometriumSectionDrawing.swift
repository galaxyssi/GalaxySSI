import SwiftUI

private typealias EndometriumSection = GalaxySSIHealthAtlasEndometriumGeometry
private typealias EndometriumTissue = GalaxySSIHealthAtlasEndometriumMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func endometriumContext(_ reveal: Double) {
    line(120,39,135,42,0xBF8A83,4); line(225,42,240,39,0xBF8A83,4)
    fill(EndometriumSection.uterus,0xEAB6A3); stroke(EndometriumSection.uterus,0x9D6268,1.6)
    fill(EndometriumSection.uterineCavity,EndometriumSection.cavity); stroke(EndometriumSection.uterineCavity,EndometriumSection.lining,2.8)
    stroke(EndometriumSection.guidePath,0xA8BDB7,1.2)
    if reveal > 0 { stroke(EndometriumSection.guidePath.trimmedPath(from: 0,to: CGFloat(reveal)),Self.teal,2.2) }
    disc(199,54,2.5,Self.teal,border: Self.cream)
  }
  func endometriumSection(_ frame: GalaxySSIHealthAtlasEndometriumMotion.Frame, section: GalaxySSIHealthAtlasEndometriumGeometry.Section) {
    fill(EndometriumSection.field,EndometriumSection.cavity)
    gradient(Path(roundedRect: CGRect(x: 106, y: 273, width: 148, height: 52), cornerRadius: 6),281,325,0xD39083,0xE3AD91)
    for i in 0...11 {
      let x = 112 + Double(i % 4) * 34, y = 289 + Double(i / 4) * 13 + Double(i % 3) * 1.8
      var path = Path(); path.move(to: CGPoint(x: x, y: y))
      path.addCurve(to: CGPoint(x: x + 31, y: y - 1), control1: CGPoint(x: x + 6, y: y - 4), control2: CGPoint(x: x + 18, y: y + 3))
      stroke(path,0xAF736F,1.5)
    }
    gradient(Path(CGRect(x: 106, y: 244, width: 148, height: 37)),244,281,0xDDA2B3,0xD490A6)
    if frame.top < EndometriumTissue.basal {
      var functional = context; functional.clip(to: Path(CGRect(x: 106, y: 117, width: 148, height: 127)))
      copy(functional).gradient(section.tissue,147,244,0xF9DDD6,0xEDBEC9)
    }
    line(106,244,254,244,0xBF869D,0.9); line(106,281,254,281,0xA5707C,1.1)
    endometriumStroma(frame)
    stroke(section.profile,frame.erosion != nil || frame.step == 4 ? 0xB7788A : EndometriumSection.lining,3)
    for (i, x) in EndometriumTissue.glandSites.enumerated() {
      endometriumGland(x,top: EndometriumTissue.surface(x,top: frame.top,erosion: nil),bend: frame.secretory,index: i,t: frame.t,secreting: frame.step == 2,tissue: section.tissue)
    }
    if frame.step == 4 { endometriumRepair(frame.t) }
    if let erosion = frame.erosion {
      let radius = 8 * EndometriumTissue.ramp(erosion,from: 0.56,to: 0.96)
      endometriumOutside(section.tissue).endometriumRepairEdge(EndometriumTissue.glandSites[1],radius: radius)
    }
    stroke(EndometriumSection.field,0x9C8586,1.2)
  }
  private func endometriumStroma(_ frame: GalaxySSIHealthAtlasEndometriumMotion.Frame) {
    for i in 0...40 {
      guard let cell = EndometriumTissue.stroma(frame,index: i) else { continue }
      var local = context; local.translateBy(x: cell.x, y: cell.y); local.rotate(by: .degrees(cell.angle))
      copy(local).fill(Path(ellipseIn: CGRect(x: -cell.rx, y: -cell.ry, width: 2 * cell.rx, height: 2 * cell.ry)),cell.inBase ? 0xAC7087 : 0xB87B92)
    }
  }
}
