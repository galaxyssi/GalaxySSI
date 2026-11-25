import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthAtlasWholeBodyActions: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  let language: String
  let open: (GalaxySSIHealthAtlasState.Tab, Bool) -> Void
  @ScaledMetric(relativeTo: .caption) private var actionFontSize: CGFloat = 13
  private var hasMetrics: Bool { !GalaxySSIHealthAtlasMetrics.forEntry(entry.id).isEmpty }
  private var context: String {
    entry.systems.compactMap(atlas.entry).filter { $0.id != entry.id }
      .map { GalaxySSIHealthAtlasText.get($0.name, language) }.joined(separator: " \u{00b7} ")
  }
  var body: some View {
    VStack(spacing: 0) {
      Button { open(.structure, false) } label: {
        HStack(spacing: 10) {
          thumbnail
          VStack(alignment: .leading, spacing: 4) {
            Text(GalaxySSIHealthAtlasText.get(entry.name, language))
              .fixedSize(horizontal: false, vertical: true)
            if !context.isEmpty {
              Text(context).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.right").foregroundColor(.secondary).accessibilityHidden(true)
        }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("atlas-whole-structure-" + entry.id)
      Divider()
      HStack(alignment: .top, spacing: 0) {
        action("structure", label: "structure", symbol: "square.3.layers.3d", tab: .structure)
        action("metrics", label: "quick_metrics", symbol: "person.crop.rectangle", tab: .values)
        action("trend", label: "quick_trend", symbol: "chart.bar", tab: .values, showTrend: true, enabled: hasMetrics)
      }.accessibilityIdentifier("atlas-whole-actions")
    }.background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
      .accessibilityIdentifier("atlas-whole-selection")
  }
  @ViewBuilder private var thumbnail: some View {
    if let asset = atlas.plate(for: entry.id)?.asset, let image = UIImage(named: asset) {
      Image(uiImage: image).resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
    } else {
      Image(systemName: "square.stack.3d.up").foregroundColor(.green).frame(width: 38, height: 38).accessibilityHidden(true)
    }
  }
  private func action(_ id: String, label: String, symbol: String, tab: GalaxySSIHealthAtlasState.Tab,
                      showTrend: Bool = false, enabled: Bool = true) -> some View {
    Button { open(tab, showTrend) } label: {
      VStack(spacing: 3) {
        Image(systemName: symbol).font(.system(size: 16)).foregroundColor(enabled ? .green : .secondary)
        Text(GalaxySSIHealthAtlasText.get("health_atlas_" + label, language))
          .font(.system(size: actionFontSize)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          .foregroundColor(enabled ? .primary : .secondary)
      }.padding(.vertical, 5).padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .top).contentShape(Rectangle())
    }.buttonStyle(.plain).disabled(!enabled).accessibilityIdentifier("atlas-whole-action-" + id)
  }
}
