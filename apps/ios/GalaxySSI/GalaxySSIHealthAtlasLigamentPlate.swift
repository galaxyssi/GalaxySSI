import CoreGraphics

enum GalaxySSIHealthAtlasLigamentPlate {
  static let width = 360.0, height = 280.0, top = 8.0
  static let aclFemur = CGPoint(x:162,y:104)
  static let aclTibia = CGPoint(x:191,y:185)
  static let pclFemur = CGPoint(x:207,y:108)
  static let pclTibia = CGPoint(x:163,y:155)
  static let tibia = CGPoint(x:232,y:212)
  static func display(_ point: CGPoint) -> CGPoint { CGPoint(x:point.x,y:point.y+top) }
  static func emphasis(_ t: Double) -> Double {
    let phase = t.isFinite ? min(1,max(0,t)) : 0
    return phase*phase*(3-2*phase)
  }
}
