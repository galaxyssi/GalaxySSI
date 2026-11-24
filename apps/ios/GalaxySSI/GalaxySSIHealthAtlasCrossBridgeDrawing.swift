import SwiftUI

extension GalaxySSIHealthAtlasMovementDrawing {
  func crossBridge(_ time: Double) {
    let pose = Motion.bridgePose(time), tip = pose.tip
    let panel = Path(roundedRect: CGRect(x: 24, y: 231, width: 292, height: 100), cornerRadius: 8)
    fill(panel, 0xF9F6ED); stroke(panel, 0xDDCBB8, 1)
    var local = context; local.clip(to: Path(CGRect(x: 38, y: 238, width: 185, height: 67)))
    let art = copy(local)
    for index in 0...11 {
      let x = 29 + Double(index) * 17 + pose.actinOffset
      art.oval(x, 257, 9, 6, Self.teal); art.oval(x + 6, 252, 8, 5, 0x6AA59C)
    }
    line(46, 299, 208, 299, Self.scarlet, 8)
    line(160, 299, tip.x + 8, tip.y + 4, Self.scarlet, 5)
    oval(tip.x, tip.y, 10, 5, Self.scarlet); oval(tip.x - 3, tip.y - 1, 4, 2, 0xD99589)
    for stage in Motion.CrossBridge.allCases {
      oval(244 + Double(stage.rawValue) * 15, 275, 3.2, 3.2, stage == pose.stage ? Self.scarlet : 0xCFC3B7)
    }
    label(170, 320, pose.stage.title)
  }
}
