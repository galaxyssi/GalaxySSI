import SwiftUI

struct GalaxySSIHealthAtlasMaterialResponseView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  @Environment(\.displayScale) private var displayScale
  @State private var measuredWidth: CGFloat = 340
  static func description(_ kind: GalaxySSIHealthAtlasPhysiology.Kind, language: String) -> String {
    let prefix = kind == .calfPump ? "calf_pump" : kind == .alveolarDiffusion ? "diffusion" : kind == .cartilageCompression ? "compression" : "bone_bending"
    return GalaxySSIHealthAtlasText.get("health_atlas_" + prefix + "_diagram", language)
  }
  private var identifier: String {
    model.kind == .calfPump ? "atlas-calf-pump" : model.kind == .alveolarDiffusion ? "atlas-diffusion-layer" :
      model.kind == .cartilageCompression ? "atlas-cartilage-compression" : "atlas-bone-bending"
  }
  var body: some View {
    if model.kind.hasMaterialResponse {
      Canvas { context, size in
        let scale = min(size.width / 340, size.height / 156)
        guard scale > 0 else { return }
        var local = context
        local.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 156 * scale) / 2)
        local.scaleBy(x: scale, y: scale)
        let art = GalaxySSIHealthAtlasMaterialResponseDrawing(context: local, language: language)
        switch model.kind {
        case .calfPump: art.calfPump(model)
        case .alveolarDiffusion: art.exchange(model)
        case .cartilageCompression: art.cartilage(model)
        case .boneBending: art.bone(model)
        default: break
        }
      }.frame(height: min((measuredWidth * 0.51 * displayScale).rounded() / max(1, displayScale), 170))
        .background(GeometryReader { proxy in
          Color.clear.preference(key: GalaxySSIHealthAtlasMaterialResponseWidth.self, value: proxy.size.width)
        })
        .onPreferenceChange(GalaxySSIHealthAtlasMaterialResponseWidth.self) { width in
          if width.isFinite, width > 0, width != measuredWidth { measuredWidth = width }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.description(model.kind, language: language))
        .accessibilityValue(GalaxySSIHealthAtlasPhysiologyText.result(model, language: language) + "; " +
          GalaxySSIHealthAtlasPhysiologyText.companion(model, language: language))
        .accessibilityIdentifier(identifier)
    }
  }
}

private struct GalaxySSIHealthAtlasMaterialResponseWidth: PreferenceKey {
  static let defaultValue: CGFloat = 340
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
