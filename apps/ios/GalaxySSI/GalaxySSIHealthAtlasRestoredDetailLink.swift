import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasRestoredDetailLink: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  var enabled = true
  private var location: GalaxySSIHealthAtlasLessonNavigation.Location { .init(entryID: entry.id, depth: depth) }
  var body: some View {
    NavigationLink(isActive: Binding(get: { enabled && state.restoredDetailChildren[location.key] != nil },
      set: { if !$0 && enabled { state.closeRestoredDetail(location) } })) {
      if let next = state.restoredDetailChildren[location.key], let target = atlas.entry(next.entryID) {
        GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: next.depth)
      }
    } label: { EmptyView() }.hidden()
  }
}
