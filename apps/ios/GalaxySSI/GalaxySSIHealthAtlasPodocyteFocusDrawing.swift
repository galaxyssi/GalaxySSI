import SwiftUI

private typealias PodocyteFocus = GalaxySSIHealthAtlasPodocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private func podocyteAlpha(_ alpha: Double) -> Self {
    var local = context; local.opacity *= Double(Int(255 * PodocyteFocus.safe(alpha))) / 255
    return copy(local)
  }
  func podocyteFenestraFocus(_ f: Double) {
    let focus = PodocyteFocus.fenestrae[0] + (PodocyteFocus.fenestrae[7] - PodocyteFocus.fenestrae[0]) * f
    for x in PodocyteFocus.fenestrae {
      let alpha = PodocyteFocus.focusAlpha(x,center: focus,width: 34)
      guard alpha > 0 else { continue }
      let y = PodocyteFocus.wallY(x) - 6
      podocyteAlpha(alpha).stroke(Path(ellipseIn: CGRect(x: x - 6, y: y - 9, width: 12, height: 17)),0x9F4960,2)
    }
  }
  func podocyteBasementFocus(_ f: Double) {
    let center = PodocyteFocus.left + (PodocyteFocus.right - PodocyteFocus.left) * f
    for i in 0...53 {
      let x = PodocyteFocus.left + 2 + Double(i) * 4, alpha = PodocyteFocus.focusAlpha(x,center: center,width: 34)
      if alpha > 0 { podocyteAlpha(alpha).line(x,PodocyteFocus.wallY(x) + 6.5,x + 4,PodocyteFocus.wallY(x + 4) + 6.5,0xA1732E,2.8) }
    }
  }
  func podocyteSlitFocus(_ f: Double) {
    let focus = PodocyteFocus.slits[6] - (PodocyteFocus.slits[6] - PodocyteFocus.slits[0]) * f
    for x in PodocyteFocus.slits {
      let alpha = PodocyteFocus.focusAlpha(x,center: focus,width: 37)
      if alpha > 0 { podocyteAlpha(alpha).podocyteDiaphragm(x,color: 0x69458C,weight: 3.3) }
    }
  }
}
