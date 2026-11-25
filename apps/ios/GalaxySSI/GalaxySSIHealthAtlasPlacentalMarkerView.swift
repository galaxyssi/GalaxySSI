import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasPlacentalMarkerView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  var resetToken: Int = 0
  private func t(_ suffix: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_placental_marker_" + suffix, language) }
  var body: some View {
    GalaxySSIHealthAtlasTeachingPlayback(caption: t("caption"), playLabel: t("play"), pauseLabel: t("pause"),
      duration: model.result > 0 ? 2.3 : 0, modelKey: model.inputs, resetToken: resetToken,
      playIdentifier: "atlas-placental-marker-play", diagramIdentifier: "atlas-placental-marker-diagram",
      diagramDescription: String(format: t("diagram"),
        GalaxySSIHealthAtlasPhysiologyText.number(model.companionValue, language: language),
        GalaxySSIHealthAtlasPhysiologyText.number(model.result, language: language)),
      heightRatio: 0.58, maximumHeight: 200) { fraction in
        Canvas { context, size in
          let scale = min(size.width / 340, size.height / 183)
          guard scale > 0, let amounts = GalaxySSIHealthAtlasPlacentalAmounts(total: model.input(0), finalTransfer: model.result, phase: fraction) else { return }
          var local = context
          local.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 183 * scale) / 2)
          local.scaleBy(x: scale, y: scale)
          GalaxySSIHealthAtlasPlacentalMarkerDrawing(context: local, language: language)
            .draw(amounts: amounts, transfer: model.result, phase: fraction)
        }
      }
  }
}

private struct GalaxySSIHealthAtlasPlacentalMarkerDrawing {
  let context: GraphicsContext
  let language: String
  private func color(_ value: UInt32) -> Color { GalaxySSIHealthAtlasIllustratedDrawing.color(value) }
  func draw(amounts: GalaxySSIHealthAtlasPlacentalAmounts, transfer: Double, phase: Double) {
    lane(top: 13, units: amounts.maternal, title: "maternal", tint: 0xEFDADB)
    lane(top: 119, units: amounts.fetal, title: "fetal", tint: 0xD4E7E9)
    for i in 0...12 {
      let x = 27 + Double(i) * 24
      oval(x - 13, 82, x + 13, 102, i.isMultiple(of: 2) ? 0xB0C8C3 : 0xBFD4D2)
    }
    label(t("barrier"), 94, 96, 122)
    if transfer > 0 && phase < 1 {
      let x = 225 + 19 * phase, y = 63 + 67 * phase
      oval(x - 4.4, y - 4.4, x + 4.4, y + 4.4, 0xB47A33)
      oval(x - 2.8, y - 2.7, x + 0.4, y + 0.5, 0xFFDFAC)
    }
  }
  private func lane(top: Double, units: Double, title: String, tint: UInt32) {
    context.fill(Path(roundedRect: CGRect(x: 13, y: top, width: 314, height: 51), cornerRadius: 13), with: .color(color(tint)))
    label(t(title), 72, top + 22, 110)
    label(String(format: t("amount_label"), GalaxySSIHealthAtlasPhysiologyText.number(units, digits: 1, language: language)),
      248, top + 43, 148)
    let slots = 8 * units / 120
    for index in 0..<8 {
      let x = 151 + Double(index) * 21, y = top + 18
      let ring = Path(ellipseIn: CGRect(x: x - 6.3, y: y - 6.3, width: 12.6, height: 12.6))
      context.stroke(ring, with: .color(color(0xAC9693)), lineWidth: 1.2)
      let share = min(1, max(0, slots - Double(index)))
      if share > 0 {
        let radius = 5.3 * sqrt(share)
        oval(x - radius, y - radius, x + radius, y + radius, 0xB47A33)
      }
    }
  }
  private func t(_ suffix: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_placental_marker_" + suffix, language) }
  private func oval(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ tint: UInt32) {
    context.fill(Path(ellipseIn: CGRect(x: left, y: top, width: right - left, height: bottom - top)), with: .color(color(tint)))
  }
  private func label(_ text: String, _ x: Double, _ baseline: Double, _ available: Double) {
    let natural = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12.5)]).width
    let size = 12.5 * min(1, available / max(1, natural))
    context.draw(Text(verbatim: text).font(.system(size: size)).foregroundColor(GalaxySSIHealthAtlasIllustratedDrawing.color(0x4C414A)),
      at: CGPoint(x: x, y: baseline - UIFont.systemFont(ofSize: size).ascender), anchor: .top)
  }
}
