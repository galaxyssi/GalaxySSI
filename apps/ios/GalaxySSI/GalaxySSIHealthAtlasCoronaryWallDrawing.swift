import SwiftUI

private typealias CoronaryWall = GalaxySSIHealthAtlasCoronaryGeometry
private typealias CoronaryWallRoutes = GalaxySSIHealthAtlasCoronaryRoutes
private typealias CoronaryWallTime = GalaxySSIHealthAtlasCoronaryMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func coronaryWall(step: Int, t: Double, squeeze: Double) {
    label("coronary_story_lv_wall",180,241,212)
    let crowding = CoronaryWallTime.crowding(squeeze), time = CoronaryWallTime.wallTime(step: step,t: t)
    gradient(CoronaryWall.wallSlice,250,326,0xFFE4CD,0xE6A39B); stroke(CoronaryWall.wallSlice,0xBB827A,1.5)
    for side in [-1.0,1] {
      for row in 0...1 {
        stroke(CoronaryWall.wallFiber(squeeze: squeeze,side: side,row: row),row == 0 ? 0xCD8C82 : 0xFBE0C9,2.5)
      }
    }
    stroke(CoronaryWallRoutes.arteriole.path,CoronaryWall.artery,5 + 5 * crowding)
    stroke(CoronaryWallRoutes.arteriole.path,CoronaryWall.arteryFill,2 + 4 * crowding)
    stroke(CoronaryWallRoutes.venule.path,CoronaryWall.vein,6.8); stroke(CoronaryWallRoutes.venule.path,CoronaryWall.veinFill,3.8)
    var local = context; local.translateBy(x: 180, y: 290); local.scaleBy(x: 1, y: crowding); local.translateBy(x: -180, y: -290)
    let capillary = copy(local)
    for (i, branch) in CoronaryWallRoutes.capillaries.enumerated() {
      capillary.stroke(branch.path,i == 1 ? 0xA15D73 : 0xB76B79,3.4)
      capillary.coronaryStream(branch,time: time + Double(i) * 0.16,speed: 1.32,count: 2,color: Self.cream,strength: 0.38 + 0.62 * crowding)
    }
    coronaryStream(CoronaryWallRoutes.arteriole,time: time,speed: 1.65,count: 2,color: Self.cream,strength: 0.45 + 0.55 * crowding)
    coronaryStream(CoronaryWallRoutes.venule,time: Double(step - 1) + t,speed: 1.05,count: 2,color: Self.cream)
    for i in 0...3 {
      let frame = CoronaryWallTime.oxygen(time: time,index: i,crowding: crowding)
      var oxygen = context; oxygen.opacity *= Double(frame.alpha) / 255
      copy(oxygen).fill(Path(ellipseIn: CGRect(x: frame.x - 2.6, y: frame.y - 1.6, width: 5.2, height: 3.2)),CoronaryWall.oxygen)
    }
    if step == 2 {
      for side in [-1.0,1] {
        let tip = 290 + side * (13 - 5 * squeeze)
        arrow(177,tip + side * 13,177,tip,0x905864)
      }
    }
    line(65,296,65,333,CoronaryWall.leader,1); line(191,307,191,333,CoronaryWall.leader,1); line(288,295,288,333,CoronaryWall.leader,1)
    label("coronary_story_arteriole",65,349,100); label("coronary_story_capillaries",191,349,125); label("coronary_story_venule",288,349,100)
  }
}
