import SwiftUI

struct GalaxySSIHealthAtlasBarrierView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    let motion = GalaxySSIHealthAtlasBarrierMotion(chapter: story.chapter(phase), fraction: story.fraction(phase))
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2); local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      art.barrierScene(step: motion.chapter, t: motion.fraction)
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-epidermal-barrier-art")
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func barrierScene(step: Int, t: Double) {
    switch step {
    case 0: epidermis(t, flatten: false, shed: false)
    case 1: epidermis(t, flatten: true, shed: false)
    case 2: lipids(t)
    case 3: compareWater(t)
    default: epidermis(t, flatten: true, shed: true)
    }
  }
  private func epidermis(_ t: Double, flatten: Bool, shed: Bool) {
    let x = 45.0
    gradient(Path(roundedRect: CGRect(x: x, y: 110, width: 270, height: 186), cornerRadius: 15), 98, 315, 0xFFEFDD, 0xD9A5A1)
    for row in 0...4 {
      let y = Double(277 - row * 31)
      for col in 0...6 {
        let cx = Double(65 + col * 38 + (row % 2 == 1 ? 12 : 0))
        if cx > 304 || (col == 3 && flatten && !shed) { continue }
        barrierCell(cx, y, Double(15 + row), 13.5 - Double(row) * 1.7, row > 2 ? Self.sand : Self.peach, Self.violet)
      }
    }
    for row in 0...2 {
      for col in 0...5 {
        if shed && row == 0 && col == 3 { continue }
        let shift = shed && row == 1 && col == 3 ? 14 * t : 0
        barrierPlate(Double(53 + col * 44 + row % 2 * 8), Double(106 + row * 14) - shift, 40, 10)
      }
    }
    line(x + 7, 297, 308, 297, Self.coral, 2)
    if !flatten {
      let gap = 9 + 8 * t
      barrierCell(163 - gap, 274, 13, 13, Self.sand, Self.violet)
      barrierCell(163 + gap, 273 - 12 * t, 13, 13, Self.sand, Self.violet)
      arrow(162, 252, 162, 226 - 33 * t, Self.teal)
    } else if !shed {
      let y = GalaxySSIHealthAtlasBarrierMotion.ascent(t)
      if t < 0.88 { barrierCell(181, y, 16 + 6 * t, 13 - 8 * t, Self.sand, Self.violet) }
      else { barrierPlate(159, y - 5, 44, 10) }
    } else {
      let px = 207 + 23 * t, py = 111 - 47 * t
      var rotated = context; rotated.translateBy(x: px, y: py); rotated.rotate(by: .degrees(18 * t)); rotated.translateBy(x: -px, y: -py)
      copy(rotated).barrierPlate(185 + 23 * t, 106 - 47 * t, 44, 10)
      arrow(268, 91, 268, 63 - 15 * t, Self.sienna); arrow(185, 239, 185, 203 - 21 * t, Self.teal)
    }
    label("barrier_basal", 94, 329, 133); line(94, 314, 94, 296, Self.coral, 1.2)
    label("barrier_cornea", 104, 66, 153); line(104, 73, 104, 105, Self.sienna, 1.2)
  }
  private func lipids(_ t: Double) {
    label("barrier_cornea", 180, 48, 240)
    for row in 0...2 {
      for col in 0...3 { barrierPlate(Double(31 + col * 80 + row % 2 * 13), Double(74 + row * 33), 68, 24) }
    }
    for row in 0...2 {
      for index in 0...3 {
        let x = Double(43 + index * 75), v = min(1, max(0, t * 1.45 - Double(index) * 0.12)), y = Double(108 + row * 32)
        line(x, y - 1, x + 20 + 30 * v, y - 1, Self.teal, 2.4); line(x, y + 4, x + 20 + 30 * v, y + 4, Self.blue, 1.6)
      }
    }
    for i in 0...4 {
      let x = Double(56 + i * 62)
      oval(x - 27, 221, x + 27, 275, top: 126, bottom: 300, from: 0xFFE6D5, to: 0xD99B9A, border: Self.coral)
      disc(x, 254, 8, Self.violet)
      let f = min(1, max(0, t * 1.15 - 0.07 * Double(i))), y = 234 - 45 * f
      for j in 0...2 { line(x - 5, y + Double(j) * 4, x + 5, y + Double(j) * 4, Self.teal, 2) }
    }
    label("barrier_intercellular", 180, 195, 235); label("barrier_granular", 180, 310, 225)
  }
  private func compareWater(_ t: Double) {
    for i in 0...1 {
      let broken = i == 1, x = Double(22 + i * 162)
      rounded(x, 92, x + 154, 281, 9, 0xF9F6EA)
      for row in 0...1 {
        let y = Double(153 + 20 * row), barrierY = Double(171 + row * 20)
        barrierPlate(x + 8, y, 54, 15); barrierPlate(x + 64, y, 26, 15); barrierPlate(x + 92, y, 54, 15)
        if !broken { line(x + 10, barrierY, x + 144, barrierY, Self.teal, 2.2) }
        else {
          line(x + 10, barrierY, x + 60, barrierY, Self.teal, 2.2); line(x + 93, barrierY, x + 144, barrierY, Self.teal, 2.2)
        }
      }
      for j in 0...5 {
        let f = GalaxySSIHealthAtlasBarrierMotion.escape(t, disrupted: broken, index: j)
        let cx = x + Double(62 + j % 2 * 29) + 2 * wave(f), y = max(Double(105 + 4 * j), Double(228 + j * 8) - 128 * f)
        disc(cx, y, 3.8 + Double(j % 2), Self.blue, border: Self.cream)
      }
      label(broken ? "barrier_disrupted" : "barrier_intact", x + 77, 309, 150)
    }
    line(180, 97, 180, 278, 0xC1CCCA, 1.1)
  }
  private func barrierCell(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ fill: UInt32, _ nucleus: UInt32) {
    oval(x - rx, y - ry, x + rx, y + ry, fill: fill, border: Self.coral)
    disc(x - rx * 0.12, y + 0.5, max(2, ry * 0.34), nucleus); disc(x - rx * 0.30, y - ry * 0.51, 1.4, Self.cream)
  }
  private func barrierPlate(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    rounded(x, y, x + w, y + h, 4, Self.sand); line(x + 4, y + 2.5, x + w - 4, y + 2.5, Self.cream, 1.1)
  }
}
