import SwiftUI

enum GalaxySSIHealthFeature: String, CaseIterable, Identifiable {
  case care, agenda, recordCenter, originals, manual, records, catalog, weekly, assistant, sources, files, profile, privacy, body
  var id: String { rawValue }
  var label: (key: String, fallback: String, icon: String) {
    switch self {
    case .care: return ("care.title", "Care", "waveform.path.ecg")
    case .agenda: return ("agenda.title", "Health Actions", "checklist")
    case .recordCenter: return ("record_center.title", "Health Record Center", "chart.bar.xaxis")
    case .originals: return ("originals.title", "Health Originals", "doc.on.doc")
    case .manual: return ("manual", "Record measurement", "square.and.pencil")
    case .records: return ("overview_list.all_records", "All records", "clock.arrow.circlepath")
    case .catalog: return ("catalog.title", "Measurement Catalog", "list.bullet.rectangle")
    case .weekly: return ("weekly.title", "Weekly Health Report", "chart.bar.xaxis")
    case .assistant: return ("assistant.title", "Health Assistant", "person.crop.square")
    case .sources: return ("sources", "Devices & Data Sources", "externaldrive.connected.to.line.below")
    case .files: return ("data_files.title", "Data and Files", "square.and.arrow.up")
    case .profile: return ("profile.title", "Health Profile", "person.text.rectangle")
    case .privacy: return ("privacy.title", "Health Privacy", "lock.shield")
    case .body: return ("body.title", "Body Explorer", "figure.stand")
    }
  }
  func title(language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + label.key, fallback: label.fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthFunctionsView<Destination: View>: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let destination: (GalaxySSIHealthFeature) -> Destination
  let manual: () -> Void
  var body: some View {
    List {
      ForEach(GalaxySSIHealthFeature.allCases) { feature in
        if feature == .manual {
          Button(action: manual) { row(feature) }.buttonStyle(.plain)
        } else {
          NavigationLink { destination(feature) } label: { row(feature) }
        }
      }
    }
    .listStyle(.plain).disabled(scene != .active)
    .navigationTitle(GalaxySSILocalization.string("galaxyssi.health.functions", fallback: "Health functions", language: language))
    .galaxySSIHealthTheme().accessibilityIdentifier("health-functions-list")
  }
  private func row(_ feature: GalaxySSIHealthFeature) -> some View {
    HStack(spacing: 12) {
      Image(systemName: feature.label.icon).foregroundColor(GalaxySSIHealthTheme.accent)
        .frame(width: 24, height: 24).accessibilityHidden(true)
      Text(feature.title(language: language)).foregroundColor(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      if feature == .manual { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(.secondary).accessibilityHidden(true) }
    }.frame(minHeight: 52).contentShape(Rectangle())
      .accessibilityIdentifier("health-feature-" + feature.id)
  }
}
