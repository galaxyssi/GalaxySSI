import SwiftUI
import UIKit

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let distalMembrane: UInt32 = 0x915957, sodium: UInt32 = 0x9C401E, chloride: UInt32 = 0x685084
  private static let potassium: UInt32 = 0x28684D, distalWater: UInt32 = 0x1F6484
  func distalExchange(_ step: Int, _ t: Double) {
    rounded(18, 54, 342, 142, 12, 0xD9EEF1); rounded(18, 220, 342, 302, 12, 0xEBEEE2)
    gradient(Path(CGRect(x: 18, y: 124, width: 324, height: 118)), 124, 242, 0xF2E0D3, 0xD6A7A1)
    var shell = Path(); shell.move(to: CGPoint(x: 107, y: 124))
    shell.addQuadCurve(to: CGPoint(x: 101, y: 178), control: CGPoint(x: 100, y: 133))
    shell.addQuadCurve(to: CGPoint(x: 111, y: 242), control: CGPoint(x: 102, y: 222)); shell.addLine(to: CGPoint(x: 276, y: 242))
    shell.addQuadCurve(to: CGPoint(x: 288, y: 175), control: CGPoint(x: 287, y: 223))
    shell.addQuadCurve(to: CGPoint(x: 281, y: 124), control: CGPoint(x: 289, y: 134)); shell.closeSubpath()
    gradient(shell, 124, 242, 0xFFEDDD, 0xE6AD9F)
    line(18, 124, 342, 124, Self.distalMembrane, 2.6); line(18, 242, 342, 242, Self.distalMembrane, 2.6)
    stroke(shell, Self.distalMembrane, 1.8)
    var folds = Path()
    for x in stride(from: 176.0, through: 217.0, by: 10) {
      folds.move(to: CGPoint(x: x, y: 242)); folds.addCurve(to: CGPoint(x: x + 1, y: 217), control1: CGPoint(x: x - 3, y: 233), control2: CGPoint(x: x + 7, y: 223))
    }
    folds.move(to: CGPoint(x: 272, y: 242)); folds.addCurve(to: CGPoint(x: 273, y: 215), control1: CGPoint(x: 269, y: 232), control2: CGPoint(x: 276, y: 220))
    stroke(folds, 0xBB7D77, 1.45)
    oval(49, 166, 80, 190, fill: 0xC793A1, border: 0xA67688); oval(302, 173, 327, 194, fill: 0xC793A1, border: 0xA67688)
    oval(202, 177, 237, 202, fill: 0xBA8294, border: 0x9B6378); oval(207, 182, 221, 190, fill: 0xD2A6AE, border: 0xD2A6AE)
    line(100, 128, 112, 128, Self.distalMembrane, 3.6); line(277, 128, 289, 128, Self.distalMembrane, 3.6)
    label("distal_exchange_lumen", 180, 40, 242); label("distal_exchange_tissue", 180, 323, 246)
    distalGate(187, 124, 54, step == 1 || step == 4 ? 0xA16A54 : 0xC1B1AD)
    distalGate(145, 242, 66, step == 2 || step == 4 ? 0xA16A54 : 0xC1B1AD)
    distalGate(248, 242, 36, step == 3 || step == 4 ? Self.chloride : 0xC1B1AD)
    switch step {
    case 0:
      distalShaft(35, 323, 79)
      distalIon("Na+", 52 + 234 * t, 68, Self.sodium); distalIon("Cl-", 70 + 234 * t, 91, Self.chloride)
      distalIon("H2O", 44 + 234 * t, 90, Self.distalWater)
      label("distal_exchange_cell", 192, 166, 148); label("distal_exchange_apical", 62, 148, 78); label("distal_exchange_basolateral", 276, 281, 122)
      line(61, 133, 61, 124, Self.distalMembrane, 1.2); line(295, 265, 295, 242, Self.distalMembrane, 1.2)
    case 1: distalNCC(t)
    case 2: distalPump(t)
    case 3: distalChloride(t)
    default:
      distalShaft(31, 107, 79); distalIon("H2O", Self.distalTransit(36, 95, t), 79, Self.distalWater)
      distalNCC(t); let delayed = min(1, max(0, t * 1.35 - 0.30)); distalPump(delayed); distalChloride(delayed)
    }
  }
  private func distalNCC(_ t: Double) {
    let y = Self.distalTransit(75, 162, t)
    distalVertical(187, 66, 166, 0x996455); line(177, y, 197, y, 0x996455, 2)
    distalIon("Na+", 174, y, Self.sodium); distalIon("Cl-", 200, y, Self.chloride)
    label("distal_exchange_ncc_label", 263, 114, 73); line(217, 118, 235, 113, Self.distalMembrane, 1.1)
  }
  private func distalPump(_ t: Double) {
    distalVertical(130, 199, 279, Self.sodium); distalVertical(161, 280, 200, Self.potassium)
    distalIon("Na+", 130, Self.distalTransit(205, 270, t), Self.sodium); distalIon("K+", 161, Self.distalTransit(268, 211, t), Self.potassium)
    label("distal_exchange_pump_label", 145, 296, 110)
  }
  private func distalChloride(_ t: Double) {
    distalVertical(248, 203, 279, Self.chloride); distalIon("Cl-", 248, Self.distalTransit(210, 271, t), Self.chloride)
    label("distal_exchange_channel", 248, 296, 91)
  }
  private func distalGate(_ x: Double, _ y: Double, _ width: Double, _ tint: UInt32) {
    rounded(x - width / 2, y - 8, x + width / 2, y + 8, 5, tint)
    rounded(x - width / 2 + 4, y - 5, x + width / 2 - 4, y + 5, 3, 0xFFF1DF)
  }
  private func distalIon(_ symbol: String, _ x: Double, _ y: Double, _ tint: UInt32) {
    rounded(x - 12, y - 8, x + 12, y + 8, 6, tint)
    context.draw(Text(verbatim: symbol).font(.system(size: 10)).foregroundColor(.white),
      at: CGPoint(x: x, y: y + 3.5 - UIFont.systemFont(ofSize: 10).ascender), anchor: .top)
  }
  private func distalVertical(_ x: Double, _ from: Double, _ to: Double, _ tint: UInt32) {
    let tail = to > from ? to - 7 : to + 7
    line(x, from, x, to, tint, 1.5); line(x - 4, tail, x, to, tint, 1.5); line(x + 4, tail, x, to, tint, 1.5)
  }
  private func distalShaft(_ from: Double, _ to: Double, _ y: Double) {
    line(from, y, to, y, Self.distalWater, 1.5)
    line(to - 7, y - 4, to, y, Self.distalWater, 1.5); line(to - 7, y + 4, to, y, Self.distalWater, 1.5)
  }
  private static func distalTransit(_ from: Double, _ to: Double, _ t: Double) -> Double {
    let u = min(1, max(0, t)); return from + (to - from) * u * u * (3 - 2 * u)
  }
}
