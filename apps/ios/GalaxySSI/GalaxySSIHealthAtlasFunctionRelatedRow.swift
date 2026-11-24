import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasFunctionRelatedRow: View {
  let atlas: GalaxySSIHealthAtlas
  let catalogue: GalaxySSIHealthAtlasFunctionCatalogue
  let target: GalaxySSIHealthAtlas.Entry
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  let language: String
  @State private var active = false
  var body: some View {
    if depth < 32, catalogue.routes[target.id]?.contains(story.id) == true {
      Button {
        var next = state.binding(target).wrappedValue
        var function = next.functionSelection ?? .init()
        function.choose(story.id, entryID: target.id, catalogue: catalogue)
        next.functionSelection = function
        next.tab = .function
        state.binding(target).wrappedValue = next
        active = true
      } label: {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 4) {
            Text(GalaxySSIHealthAtlasFunctionText.get(story.title, language))
              .fixedSize(horizontal: false, vertical: true)
            Text(GalaxySSIHealthAtlasText.get(target.name, language))
              .font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
          }.frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary).accessibilityHidden(true)
        }.frame(minHeight: 48).contentShape(Rectangle())
      }.buttonStyle(.plain)
        .accessibilityIdentifier("atlas-related-lesson-" + target.id)
        .background(NavigationLink(isActive: $active) {
          GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1)
        } label: { EmptyView() }.hidden())
    }
  }
}
