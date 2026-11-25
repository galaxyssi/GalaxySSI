import SwiftUI

private typealias SplenicAnatomy = GalaxySSIHealthAtlasSplenicShapes
private typealias SplenicWall = GalaxySSIHealthAtlasSplenicMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func splenicLocator(step: Int, t: Double) {
    gradient(SplenicAnatomy.spleen, 30, 110, 0xF2A9A7, 0xBD7188); stroke(SplenicAnatomy.spleen, SplenicAnatomy.plum, 1.6)
    oval(42,67,54,77,fill: 0xF8DBCF,border: SplenicAnatomy.rose)
    oval(59,43,71,53,fill: 0xF8DBCF,border: SplenicAnatomy.rose)
    oval(58,84,68,92,fill: 0xF8DBCF,border: SplenicAnatomy.rose)
    stroke(SplenicAnatomy.arc(34,33,100,97,start: 185,sweep: 97), 0xF8CFBF, 1.7)
    let highlight = step == 0 ? 2.5 * SplenicWall.ease(t) : 2.5
    disc(80,72,8.5 + highlight,0xF8C9B9,border: SplenicAnatomy.plum); disc(80,72,2.7,SplenicAnatomy.plum)
    line(87,67,121,49,SplenicAnatomy.leader,1.15); line(121,49,139,49,SplenicAnatomy.leader,1.15)
    line(82,83,92,101,SplenicAnatomy.leader,1.15); line(92,101,151,101,SplenicAnatomy.leader,1.15)
    line(151,101,151,141,SplenicAnatomy.leader,1.15)
    label("splenic_filter_story_label_spleen",57,113,57); label("splenic_filter_story_label_red_pulp",178,53,70)
  }
  func splenicAnatomy() {
    gradient(Path(CGRect(x: 24, y: 141, width: SplenicWall.wallLeft - 24, height: 170)),141,311,0xFFF1E7,0xF6D9D0)
    gradient(Path(CGRect(x: SplenicWall.wallLeft, y: 141, width: 336 - SplenicWall.wallLeft, height: 170)),141,311,0xF0FAF4,0xCFE9E2)
    for i in 0...3 {
      let y = 155 + 43 * Double(i)
      line(24,y,50,y + 15,SplenicAnatomy.fiber,1.25); line(50,y + 15,87,y + 7,SplenicAnatomy.fiber,1.25)
      line(50,y + 15,74,y + 37,SplenicAnatomy.fiber,1.25); disc(50,y + 15,2.2,SplenicAnatomy.fiber)
    }
    for i in 0...2 {
      let x = 116 + 31 * Double(i)
      line(x,146,x + 15,172,SplenicAnatomy.fiber,1.25); line(x + 15,172,x - 3,187,SplenicAnatomy.fiber,1.25)
      disc(x + 15,172,2.2,SplenicAnatomy.fiber)
    }
    for i in stride(from: 0, to: SplenicWall.wallSegments.count, by: 2) {
      let top = SplenicWall.wallSegments[i], bottom = SplenicWall.wallSegments[i + 1]
      var local = context; local.translateBy(x: SplenicWall.wallLeft, y: top); local.rotate(by: .degrees(-90))
      let wall = Path(roundedRect: CGRect(x: top - bottom, y: 0, width: bottom - top, height: SplenicWall.wallRight - SplenicWall.wallLeft), cornerRadius: 5)
      let art = copy(local)
      art.gradient(wall,0,18,0xB9DBCF,0x8EBBB0); art.stroke(wall,SplenicAnatomy.sinusEdge,1.2)
      let cy = (top + bottom) / 2
      oval(203,cy - 6,211,cy + 6,fill: 0x80AFA3,border: SplenicAnatomy.sinusEdge)
    }
    for i in 0...2 {
      let f = Double(i), y = 233 + 29 * f
      line(244 + 15 * f,y,264 + 15 * f,y,0xB9D8CF,1.2); line(297 + 7 * f,y,310 + 7 * f,y,0xB9D8CF,1.2)
    }
  }
  func splenicLabels(_ step: Int) {
    label("splenic_filter_story_label_cord",87,132,120); label("splenic_filter_story_label_sinus",266,132,128)
    line(210,203,233,177,SplenicAnatomy.leader,1.1); line(233,177,260,177,SplenicAnatomy.leader,1.1)
    disc(210,203,1.8,SplenicAnatomy.leader); label("splenic_filter_story_label_slit",274,170,100)
    line(91,289,91,320,SplenicAnatomy.leader,1.1); disc(91,289,2,SplenicAnatomy.leader)
    label("splenic_filter_story_label_macrophage",108,337,165)
    switch step {
    case 0, 1:
      splenicRedCell(208,333,scale: 0.36,angle: 0); label("splenic_filter_story_label_red_cell",277,337,115)
    case 2, 3:
      splenicRedCell(208,333,scale: 0.36,angle: 0,lessFlexible: true); label("splenic_filter_story_label_less_flexible",277,337,115)
    default:
      splenicIron(208,333,scale: 1); label("splenic_filter_story_label_iron",277,337,115)
    }
  }
}
