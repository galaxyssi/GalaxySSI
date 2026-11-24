import SwiftUI
import UIKit

private typealias ThymusCells = GalaxySSIHealthAtlasThymusShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thymusAlpha(_ alpha: Int) -> Self {
    var local = context; local.opacity *= Double(min(255,max(0,alpha))) / 255
    return copy(local)
  }
  func thymusCell(_ x: Double, _ y: Double, radius: Double, color: UInt32, alpha: Int = 255) {
    let art = thymusAlpha(alpha)
    art.disc(x,y,radius + 2,0xF9FAF4); art.disc(x,y,radius,color)
    let nucleus = Path(ellipseIn: CGRect(x: x - radius * 0.62, y: y - radius * 0.52, width: radius * 0.91, height: radius * 0.94))
    thymusAlpha(alpha * 5 / 8).fill(nucleus,0xF0F4E9)
    art.disc(x + radius * 0.43,y - radius * 0.35,1.35,0xF9FAF4)
  }
  func thymusCellLabel(_ x: Double, color: UInt32, key: String, width: Double) {
    let value = GalaxySSIHealthAtlasFunctionText.get("health_atlas_" + key,language)
    let measured = (value as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]).width
    let textWidth = min(width, Double(measured))
    disc(x - textWidth / 2 - 9,338,3.4,color); label(key,x,343,width)
  }
  func thymusPresenter(_ x: Double, _ y: Double, edge: UInt32, fill: UInt32) {
    line(x - 17,y + 1,x + 13,y - 6,edge,3)
    line(x - 6,y - 15,x + 7,y + 12,edge,3); line(x - 12,y + 12,x + 7,y - 12,edge,3)
    oval(x - 13,y - 9,x + 11,y + 9,fill: fill,border: edge)
    oval(x - 4,y - 3,x + 4,y + 4,fill: 0xF4DFDE,border: edge)
  }
  func thymusTravel(_ route: GalaxySSIHealthAtlasSectionLesson.Route, t: Double, color: UInt32, radius: Double) {
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360)
    var guide = context; guide.opacity *= 160.0 / 255
    guide.stroke(path,with: .color(Self.color(color)),style: StrokeStyle(lineWidth: 1.25,lineCap: .round,lineJoin: .round,dash: [2.5,4]))
    if let end = GalaxySSIHealthAtlasFunctionPath.sample(route,position: 1,width: 360,height: 360) {
      let x = Double(end.point.x), y = Double(end.point.y)
      arrow(x - 7 * Double(end.direction.dx),y - 7 * Double(end.direction.dy),x,y,color)
    }
    at(route,GalaxySSIHealthAtlasThymusMotion.travel(t)) { thymusCell($0,$1,radius: radius,color: color) }
  }
}
