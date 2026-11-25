import SwiftUI

struct GalaxySSIHealthAtlasRetinaPathView: View {
  let atlas: GalaxySSIHealthAtlas
  let model: GalaxySSIHealthAtlas.Mechanism
  let stage: Int
  let language: String
  let select: (Int) -> Void
  let open: (String) -> Void
  @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 11
  var body: some View {
    if let destinations = GalaxySSIHealthAtlasRetinaPath.destinations(stage: stage), model.stages.count == 4 {
      VStack(alignment: .leading, spacing: 10) {
        GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-retina-figure", header: { EmptyView() }, artwork: {
        VStack(spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
          VStack(spacing: 6) {
            heading("sensory_retinal_rod_route")
            node(0)
            Image(systemName: "arrow.down").foregroundColor(.secondary).accessibilityHidden(true)
            node(1)
          }.frame(maxWidth: .infinity)
          VStack(spacing: 6) {
            heading("sensory_retinal_cone_route")
            node(2)
          }.frame(maxWidth: .infinity)
        }
        HStack {
          Image(systemName: "arrow.down.right").frame(maxWidth: .infinity)
          Image(systemName: "arrow.down.left").frame(maxWidth: .infinity)
        }.foregroundColor(.secondary).accessibilityHidden(true)
        node(3)
        }
        }, legend: {
          VStack(alignment: .leading, spacing: 5) {
            GalaxySSIHealthAtlasReservedCaption(values: model.stages.map { GalaxySSIHealthAtlasText.get($0, language) },
              selected: stage, identifier: "atlas-retina-step-text").font(.subheadline.bold())
            Text(t("sensory_retinal_scope")).font(.system(size: noteSize)).foregroundColor(.secondary)
          }
        })
        ForEach(destinations, id: \.self) { id in
          if let entry = atlas.entry(id) {
            Button { open(id) } label: {
              HStack {
                Text(GalaxySSIHealthAtlasText.get(entry.name, language)).fixedSize(horizontal: false, vertical: true)
                Spacer(); Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
              }.frame(minHeight: 44)
            }.accessibilityIdentifier("atlas-retina-open-" + id)
          }
        }
      }.accessibilityIdentifier("atlas-retinal-path")
    }
  }
  private func heading(_ key: String) -> some View {
    Text(t(key)).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
  }
  private func node(_ index: Int) -> some View {
    Button { select(index) } label: {
      VStack(spacing: 4) {
        Text(t(GalaxySSIHealthAtlasRetinaPath.nodes[index]))
        if index == 2 {
          Image(systemName: "arrow.down").accessibilityHidden(true)
          Text(t("sensory_retinal_relay_cone"))
        }
      }.font(.subheadline.bold()).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .padding(8).frame(maxWidth: .infinity, minHeight: 48)
        .foregroundColor(index == stage ? .green : .primary)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(index == stage ? Color.green : Color.secondary.opacity(0.3)))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(GalaxySSIHealthAtlasText.get(model.stages[index], language))
      .accessibilityAddTraits(index == stage ? .isSelected : []).accessibilitySortPriority(Double(4 - index))
      .accessibilityIdentifier("atlas-retina-node-" + String(index))
      .atlasAnnotationTarget("atlas-retina-figure", active: index == stage)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
