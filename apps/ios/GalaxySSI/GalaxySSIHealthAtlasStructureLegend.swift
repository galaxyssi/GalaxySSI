import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasStructureLegend: View {
  let overviewTitle: String
  let overviewDescription: String
  let landmarks: [GalaxySSIHealthAtlasLandmarks.Landmark]
  @Binding var position: Int
  let language: String
  @ScaledMetric(relativeTo: .footnote) private var titleSize: CGFloat = 14
  @ScaledMetric(relativeTo: .subheadline) private var descriptionSize: CGFloat = 14
  @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 11
  @State private var fullCopy: Copy?
  private struct Copy: Identifiable { let id: String; let title: String; let body: String }
  private var titles: [String] { [overviewTitle] + landmarks.map { GalaxySSIHealthAtlasText.get($0.title, language) } }
  private var descriptions: [String] { [overviewDescription] + landmarks.map { GalaxySSIHealthAtlasText.get($0.description, language) } }
  private var step: Int { min(landmarks.count, max(0, position)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      GalaxySSIHealthAtlasReservedCaption(values: titles, selected: step, identifier: "atlas-art-caption")
        .font(.system(size: titleSize, weight: .bold)).foregroundColor(GalaxySSIHealthTheme.accent)
      Button { fullCopy = .init(id: String(step), title: titles[step], body: descriptions[step]) } label: {
        GalaxySSIHealthAtlasReservedCaption(values: descriptions, selected: step, identifier: "atlas-art-explanation", maximumLines: 5)
          .font(.system(size: descriptionSize)).foregroundColor(.primary).contentShape(Rectangle())
      }.buttonStyle(.plain).padding(.top, 3)
      Text(t("illustration")).font(.system(size: noteSize)).foregroundColor(.secondary).padding(.top, 5)
      Text(label(step)).font(.system(size: noteSize)).foregroundColor(.secondary)
        .frame(maxWidth: .infinity).padding(.top, 5).accessibilityIdentifier("atlas-structure-step")
      HStack(spacing: 0) {
        control("chevron.left", "previous_step", enabled: step > 0, identifier: "atlas-structure-previous") { move(-1) }
        control("chevron.right", "next_step", enabled: step < landmarks.count, identifier: "atlas-structure-next") { move(1) }
      }
    }
    .alert(item: $fullCopy) { copy in
      Alert(title: Text(copy.title), message: Text(copy.body),
        dismissButton: .default(Text(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))))
    }
  }
  private func control(_ icon: String, _ key: String, enabled: Bool, identifier: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: icon).frame(maxWidth: .infinity).frame(height: 48) }
      .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
      .accessibilityLabel(GalaxySSIHealthBodyText.string(key, language: language))
      .help(GalaxySSIHealthBodyText.string(key, language: language)).accessibilityIdentifier(identifier)
  }
  private func label(_ step: Int) -> String {
    step == 0 ? t("step_overview") : String(format: t("step_position"), Int64(step), Int64(landmarks.count))
  }
  private func move(_ delta: Int) {
    let next = min(landmarks.count, max(0, step + delta))
    position = next
    if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: label(next)) }
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
