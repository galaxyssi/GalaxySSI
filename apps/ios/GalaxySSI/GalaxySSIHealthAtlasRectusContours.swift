import SwiftUI

struct GalaxySSIHealthAtlasRectusContours {
  struct Contour { let points: [CGPoint]; let closed: Bool }
  let source: Path
  let contours: [Contour]?
  init(_ source: Path) {
    self.source = source
    contours = Self.sample(source)
  }
  private static func sample(_ source: Path) -> [Contour]? {
    var result: [Contour] = [], path = Path(), start = CGPoint.zero, end = CGPoint.zero
    var length = 0.0, active = false, closed = false, valid = true
    func finish() {
      guard active, length > 0 else { return }
      let count = max(1,Int(length/3))
      let points = (0...count).map { i -> CGPoint in
        if i == 0 { return start }
        return path.trimmedPath(from:0,to:CGFloat(Double(i)/Double(count))).cgPath.currentPoint
      }
      result.append(Contour(points:points,closed:closed))
    }
    source.cgPath.applyWithBlock { element in
      let value = element.pointee
      switch value.type {
      case .moveToPoint:
        finish()
        path = Path(); start = value.points[0]; end = start; length = 0; active = true; closed = false
        path.move(to:start)
      case .addLineToPoint:
        let next = value.points[0]
        length += hypot(next.x-end.x,next.y-end.y); path.addLine(to:next); end = next
      case .addQuadCurveToPoint:
        let control = value.points[0], next = value.points[1]
        guard let segment = GalaxySSIHealthAtlasCurveLength.bezier([end,control,next]) else { valid = false; return }
        length += segment; path.addQuadCurve(to:next,control:control); end = next
      case .addCurveToPoint:
        let first = value.points[0], second = value.points[1], next = value.points[2]
        guard let segment = GalaxySSIHealthAtlasCurveLength.bezier([end,first,second,next]) else { valid = false; return }
        length += segment; path.addCurve(to:next,control1:first,control2:second); end = next
      case .closeSubpath:
        length += hypot(start.x-end.x,start.y-end.y); path.closeSubpath(); end = start; closed = true
      @unknown default: valid = false
      }
    }
    finish()
    guard valid else { assertionFailure("Invalid fixed rectus source contour"); return nil }
    return result
  }
  func deflect(_ motion: GalaxySSIHealthAtlasRectusMotion) -> Path {
    guard motion.bend >= 0.0001, let contours else { return source }
    return Path { p in
      for contour in contours {
        for (i,point) in contour.points.enumerated() {
          let mapped = motion.point(point.x,point.y)
          if i == 0 { p.move(to:mapped) } else { p.addLine(to:mapped) }
        }
        if contour.closed { p.closeSubpath() }
      }
    }
  }
}
