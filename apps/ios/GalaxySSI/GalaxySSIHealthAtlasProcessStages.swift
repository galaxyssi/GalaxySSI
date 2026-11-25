import SwiftUI

struct GalaxySSIHealthAtlasProcessStages: View {
  let stages: [String]
  let phase: Double
  let language: String
  let entryID: String
  let compact: Bool
  let selected: (Int) -> Void
  private var current: Int { min(3, Int(GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase) * 4)) }
  private func label(_ index: Int) -> String {
    String(format: GalaxySSIHealthAtlasText.get("health_atlas_stage", language), Int64(index + 1), Int64(stages.count),
      GalaxySSIHealthAtlasText.get(stages[index], language))
  }
  var body: some View {
    if stages.count == 4 {
      Group {
        if compact {
          HStack(spacing: 0) { ForEach(stages.indices, id: \.self) { stage in target(stage) } }
            .background {
              GeometryReader { geometry in
                let left = geometry.size.width / 8, length = geometry.size.width * 0.75
                Path { p in p.move(to: CGPoint(x: left, y: geometry.size.height / 2)); p.addLine(to: CGPoint(x: left + length, y: geometry.size.height / 2)) }
                  .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                let progress = min(1, GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase) * 4 / 3)
                Circle().fill(GalaxySSIHealthTheme.accent).frame(width: 6, height: 6)
                  .position(x: left + length * progress, y: geometry.size.height / 2)
              }.accessibilityHidden(true).allowsHitTesting(false)
            }
        } else {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach([0, 1, 3, 2], id: \.self) { stage in target(stage) }
          }
        }
      }.accessibilityIdentifier("atlas-process")
    }
  }
  private func target(_ stage: Int) -> some View {
    Button { selected(stage) } label: {
      VStack(spacing: 8) {
        Text("\(stage + 1)").font(.headline).lineLimit(1).minimumScaleFactor(0.7).frame(width: 32, height: 32)
          .background(stage <= current ? GalaxySSIHealthTheme.accent.opacity(0.2) : Color(.systemBackground)).clipShape(Circle())
        if !compact {
          Text(GalaxySSIHealthAtlasText.get(stages[stage], language)).font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
      }.frame(maxWidth: .infinity, minHeight: compact ? 48 : 64).padding(compact ? 0 : 8).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(label(stage))
      .accessibilityAddTraits(stage == current ? .isSelected : [])
      .accessibilitySortPriority(Double(4 - stage))
      .accessibilityIdentifier(compact ? "atlas-process-stage-" + String(stage) : "health-atlas-stage-" + entryID + "-" + String(stage))
  }
}
