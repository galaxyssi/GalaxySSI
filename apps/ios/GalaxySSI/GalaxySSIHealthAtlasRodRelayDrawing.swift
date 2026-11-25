import SwiftUI

private typealias RelayInk = GalaxySSIHealthAtlasOcularInk

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func rodRelayScene(step: Int, t: Double) {
    oval(23, 24, 338, 336, top: 36, bottom: 328, from: 0xE0EAF2, to: 0xB8D5D4, border: 0xA2BAB9)
    let left = 104.0, right = 256.0, middle = 180.0
    for i in 0...2 {
      let x = Double(124 + i * 56)
      ocularRod(x, 58, 94, 7); line(x, 94, middle, 124, Self.blue, 1.55)
      if step == 0 { disc(x, 46 + (t + Double(i) * 0.21).truncatingRemainder(dividingBy: 1) * 31, 3.4, RelayInk.retinol, border: Self.cream) }
      else if step == 1 { ocularPulse(x, 94, middle, 124, t, i, Self.blue) }
    }
    label("ocular_relay_rod", 74, 74, 76); disc(middle, 133, 11, Self.blue, border: Self.cream); label("ocular_relay_rod_bipolar", 258, 135, 111)
    line(middle, 144, middle, 171, Self.blue, 1.8); disc(middle, 181, 12, Self.violet, border: Self.cream); label("ocular_relay_aii_label", 88, 178, 118)
    if step == 2 { ocularPulse(middle, 146, middle, 170, t, 0, Self.blue) }
    arrow(172, 192, left, 231, RelayInk.transmit)
    line(190, 192, right, 231, RelayInk.suppress, 1.65); line(right - 5, 237, right + 5, 225, RelayInk.suppress, 2.2)
    if step == 3 {
      ocularPulse(172, 192, left, 228, t, 0, RelayInk.transmit); ocularPulse(190, 192, right - 3, 230, t, 0, RelayInk.suppress)
      label("ocular_relay_gap", 76, 213, 93); label("ocular_relay_glycine", 284, 213, 102)
    }
    disc(left, 249, 11, RelayInk.transmit, border: Self.cream); disc(right, 249, 11, RelayInk.suppress, border: Self.cream)
    label("ocular_relay_on", 56, 253, 66); label("ocular_relay_off", 303, 253, 68)
    if step == 4 {
      arrow(left, 261, left, 295, RelayInk.transmit); arrow(right, 261, right, 295, RelayInk.suppress)
      ocularPulse(left, 264, left, 294, t, 0, RelayInk.transmit); ocularPulse(right, 264, right, 294, t, 2, RelayInk.suppress)
      disc(left, 305, 8, RelayInk.transmit, border: Self.cream); disc(right, 305, 8, RelayInk.suppress, border: Self.cream)
      label("ocular_relay_ganglion", 179, 310, 122)
    }
  }
}
