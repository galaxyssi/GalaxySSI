import SwiftUI

enum GalaxySSIHealthCareAgentPanelLayout {
  static func limit(available: CGFloat?) -> CGFloat {
    guard let available else { return 300 }
    guard available.isFinite else { return 0 }
    return min(300, max(0, available) * 0.4)
  }
  static func bodyHeight(available: CGFloat?, header: CGFloat, content: CGFloat) -> CGFloat {
    guard header.isFinite, content.isFinite else { return 0 }
    return min(max(0, content), max(0, limit(available: available) - max(0, header)))
  }
}

enum GalaxySSIHealthCareAgentPanelText {
  static func get(_ key: String, language: String) -> String {
    func value(_ locale: String, fallback: String) -> String {
      guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
      return bundle.localizedString(forKey: key, value: fallback, table: "HealthAssessmentPanel")
    }
    let english = value("en", fallback: key)
    return value(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
  }
  static func summary(_ concern: GalaxySSIHealthCare.Concern, language: String) -> String {
    guard let pair = concern.comparison, pair.after.record == concern.assessment.record else {
      return concern.assessment.result + " " + concern.assessment.unit
    }
    let key: String
    switch pair.kind {
    case .newResult: key = "health_care_comparison_values"
    case .recordCorrection: key = "health_care_comparison_correction"
    case .historyChanged: key = "health_care_comparison_history"
    }
    func sample(_ value: GalaxySSIHealthCareComparison.Sample) -> String {
      var parts = [value.result + " " + value.unit]
      if let pulse = value.pulse { parts.append(GalaxySSIHealthCareComparison.Sample.number(pulse) + " bpm") }
      return parts.joined(separator: " / ")
    }
    return String(format: get(key, language: language), sample(pair.before), sample(pair.after))
  }
}

private struct HealthAssessmentHeaderHeight: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct HealthAssessmentBodyHeight: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct GalaxySSIHealthCareAgentPanel<Content: View>: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let availableHeight: CGFloat?
  let title: String
  let summary: String
  let priority: String?
  @Binding var expanded: Bool
  let content: () -> Content
  @State private var headerHeight: CGFloat = 0
  @State private var contentHeight: CGFloat = 0

  init(availableHeight: CGFloat?, title: String, summary: String, priority: String?, expanded: Binding<Bool>,
       @ViewBuilder content: @escaping () -> Content) {
    self.availableHeight = availableHeight; self.title = title; self.summary = summary; self.priority = priority
    _expanded = expanded; self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        Button { expanded.toggle() } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(summary).font(.footnote).foregroundColor(.secondary).lineLimit(2)
            if let priority { Text(priority).font(.caption.weight(.semibold)).lineLimit(1) }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(([title, summary] + [priority].compactMap { $0 }).joined(separator: ", ") + ". " + toggleTitle)
        .accessibilityIdentifier("agent-health-care-concern")
        Button { expanded.toggle() } label: {
          Image(systemName: expanded ? "chevron.up" : "chevron.down").frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).help(toggleTitle).accessibilityLabel(toggleTitle)
        .accessibilityIdentifier("agent-health-care-expand")
      }
      .background(GeometryReader { geometry in Color.clear.preference(key: HealthAssessmentHeaderHeight.self, value: geometry.size.height) })
      if expanded {
        ScrollView(.vertical) {
          content().frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in Color.clear.preference(key: HealthAssessmentBodyHeight.self, value: geometry.size.height) })
        }
        .frame(height: GalaxySSIHealthCareAgentPanelLayout.bodyHeight(available: availableHeight, header: headerHeight, content: contentHeight))
        .accessibilityIdentifier("agent-health-care-scroll")
      }
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, maxHeight: expanded ? GalaxySSIHealthCareAgentPanelLayout.limit(available: availableHeight) : nil, alignment: .top)
    .clipped()
    .onPreferenceChange(HealthAssessmentHeaderHeight.self) { if abs(headerHeight - $0) > 0.5 { headerHeight = $0 } }
    .onPreferenceChange(HealthAssessmentBodyHeight.self) { if abs(contentHeight - $0) > 0.5 { contentHeight = $0 } }
    .accessibilityIdentifier("agent-health-care-panel")
  }
  private var toggleTitle: String {
    GalaxySSIHealthCareAgentPanelText.get(expanded ? "health_agent_collapse" : "health_agent_expand", language: language)
  }
}
