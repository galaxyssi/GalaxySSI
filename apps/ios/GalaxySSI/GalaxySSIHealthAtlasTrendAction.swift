import SwiftUI

private struct GalaxySSIAtlasPinnedAnalysisKey: EnvironmentKey { static let defaultValue = false }
private struct GalaxySSIAtlasAnalysisSelectionKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues {
  var galaxySSIAtlasPinnedAnalysis: Bool {
    get { self[GalaxySSIAtlasPinnedAnalysisKey.self] }
    set { self[GalaxySSIAtlasPinnedAnalysisKey.self] = newValue }
  }
  var galaxySSIAtlasAnalysisSelection: String {
    get { self[GalaxySSIAtlasAnalysisSelectionKey.self] }
    set { self[GalaxySSIAtlasAnalysisSelectionKey.self] = newValue }
  }
}

enum GalaxySSIHealthAtlasTrendAction {
  /// Ephemeral identity only, never persisted in the public atlas selection cache.
  struct Identity: Equatable {
    let metric: GalaxySSIHealthMetric
    let component: GalaxySSIHealthTrend.Component
    let unit: String
    let source: GalaxySSIHealthTrend.Source
    let device: UUID?
    let origin: GalaxySSIHealthTrend.HealthOrigin
    let aggregation: GalaxySSIHealthTrend.Aggregation
    let interval: DateInterval
    let through: Date
    let calendar: Calendar
    let environmentCalendar: Calendar
    let timeZone: TimeZone
    let anchorID: UUID?
    let anchorRevision: Int?
    let unverifiedComparison: Bool
    let selection: String

    init(spec: GalaxySSIHealthTrendAnalysis.Spec, environmentCalendar: Calendar, timeZone: TimeZone, selection: String) {
      metric = spec.metric; component = spec.component; unit = spec.unit; source = spec.source
      device = spec.device; origin = spec.origin; aggregation = spec.aggregation; interval = spec.interval
      through = spec.through; calendar = spec.calendar; self.environmentCalendar = environmentCalendar; self.timeZone = timeZone
      anchorID = spec.comparisonAnchor?.id; anchorRevision = spec.comparisonAnchor?.revision
      unverifiedComparison = spec.unverifiedComparison; self.selection = selection
    }
  }
  static func ready(captured: Identity?, current: Identity, foreground: Bool, protectedData: Bool,
                    permitted: Bool, changed: Bool, hasChartData: Bool) -> Bool {
    foreground && protectedData && permitted && !changed && hasChartData && captured == current
  }
}

struct GalaxySSIHealthAtlasPinnedAnalysisButton: View {
  let enabled: Bool
  let action: () -> Void
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  var body: some View {
    Button(action: action) {
      Label(GalaxySSILocalization.string("galaxyssi.health.atlas.compare", fallback: "Analyze changes with Agent", language: language),
        systemImage: "text.bubble").frame(maxWidth: .infinity, minHeight: 48)
    }
    .buttonStyle(GalaxySSIHealthCommandStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.5)
    .padding(.horizontal, 16).padding(.vertical, 8)
  }
}
