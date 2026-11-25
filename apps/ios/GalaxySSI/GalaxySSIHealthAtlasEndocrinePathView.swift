import SwiftUI

struct GalaxySSIHealthAtlasEndocrinePathView: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  let path: GalaxySSIHealthAtlasEndocrinePath
  let stage: Int
  let language: String
  let select: (Int) -> Void
  let open: (String) -> Void
  @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 11
  private var destination: GalaxySSIHealthAtlas.Entry? { path.step(stage)?.destination.flatMap(atlas.entry) }
  private var art: GalaxySSIHealthAtlas.Plate? { destination.flatMap { atlas.plate(for: $0.id) } ?? atlas.plate(for: entry.id) }
  var body: some View {
    if path.steps.count == 4, (0..<4).contains(stage) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(0..<2) { branch in
          if let row = path.row(branch) {
            if branch == 1, !path.separateBranches {
              HStack {
                Spacer().frame(maxWidth: .infinity)
                Color.clear.frame(width: 26, height: 1)
                Image(systemName: "arrow.down").frame(maxWidth: .infinity)
              }.foregroundColor(.secondary).accessibilityHidden(true)
            }
            HStack(spacing: 0) {
              node(row[0])
              Image(systemName: branch == 1 && !path.separateBranches ? "arrow.left" : "arrow.right")
                .frame(width: 26).foregroundColor(.secondary).accessibilityHidden(true)
              node(row[1])
            }
          }
        }
        GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-endocrine-figure", preferSideNote: true,
          subjectAspectRatio: art?.aspectRatio, header: { EmptyView() }, artwork: {
            if let art {
              Image(art.asset).resizable().scaledToFit().frame(minHeight: 84, maxHeight: 110)
                .accessibilityHidden(true).atlasAnnotationSubject("atlas-endocrine-figure")
            }
          }, legend: {
            VStack(alignment: .leading, spacing: 5) {
              GalaxySSIHealthAtlasReservedCaption(values: atlas.model(entry).stages.map { GalaxySSIHealthAtlasText.get($0, language) },
                selected: stage, identifier: "atlas-endocrine-current").font(.subheadline.bold())
              Text(GalaxySSIHealthAtlasText.get(path.scope, language)).font(.system(size: noteSize)).foregroundColor(.secondary)
            }
          })
        if let destination {
          Button { open(destination.id) } label: {
            HStack {
              Text(String(format: t("endocrine_stage_details"), GalaxySSIHealthAtlasText.get(destination.name, language)))
                .fixedSize(horizontal: false, vertical: true)
              Spacer()
              Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
            }.frame(minHeight: 44)
          }.accessibilityIdentifier("atlas-endocrine-open-node")
        }
      }.accessibilityIdentifier("atlas-endocrine-path")
    }
  }
  private func node(_ index: Int) -> some View {
    Button { select(index) } label: {
      Text(GalaxySSIHealthAtlasText.get(path.steps[index].label, language)).font(.subheadline.bold())
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .padding(8).frame(maxWidth: .infinity, minHeight: 50)
        .foregroundColor(index == stage ? .green : .primary)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(index == stage ? Color.green : Color.secondary.opacity(0.3)))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).frame(maxWidth: .infinity)
      .accessibilityLabel(GalaxySSIHealthAtlasText.get(atlas.model(entry).stages[index], language))
      .accessibilityAddTraits(index == stage ? .isSelected : [])
      .accessibilitySortPriority(Double(4 - index))
      .accessibilityIdentifier("atlas-endocrine-node-" + String(index))
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
