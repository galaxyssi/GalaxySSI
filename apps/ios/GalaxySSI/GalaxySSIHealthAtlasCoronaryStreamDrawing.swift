import SwiftUI

private typealias CoronaryStream = GalaxySSIHealthAtlasCoronaryMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func coronaryStream(_ track: GalaxySSIHealthAtlasCoronaryRoutes.Track, time: Double, speed: Double, count: Int, color: UInt32, strength: Double = 1, span: Double = 1) {
    guard let length = track.length, count > 0 else { return }
    for i in 0..<count {
      guard let frame = CoronaryStream.stream(time: time,speed: speed,index: i,count: count,strength: strength,span: span,length: length), frame.alpha > 0,
        let sample = GalaxySSIHealthAtlasFunctionPath.sample(track.route,position: frame.position,width: 360,height: 360) else { continue }
      let x = Double(sample.point.x), y = Double(sample.point.y), dx = Double(sample.direction.dx), dy = Double(sample.direction.dy), size = frame.size
      var local = context; local.opacity *= Double(frame.alpha) / 255
      let art = copy(local)
      art.line(x - size * dx,y - size * dy,x,y,color,1.65)
      art.line(x,y,x - 0.55 * size * dx + 0.36 * size * dy,y - 0.55 * size * dy - 0.36 * size * dx,color,1.65)
      art.line(x,y,x - 0.55 * size * dx - 0.36 * size * dy,y - 0.55 * size * dy + 0.36 * size * dx,color,1.65)
    }
  }
}
