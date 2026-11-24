import SwiftUI

enum GalaxySSIHealthAtlasSearchSurface {
  case detail, research, standalone
  func contains(_ selection: GalaxySSIHealthAtlasState.Selection) -> Bool {
    switch self {
    case .detail: return selection.researchPresented != true && selection.tab != .simulation
    case .research: return selection.researchPresented == true
    case .standalone: return selection.researchPresented != true && selection.tab == .simulation
    }
  }
}

@MainActor
struct GalaxySSIHealthAtlasSearchNavigation: ViewModifier {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  let surface: GalaxySSIHealthAtlasSearchSurface
  @ObservedObject var memory: GalaxySSIHealthAtlasScrollMemory
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var pending: (String, GalaxySSIHealthAtlasLessonNavigation.Search)?
  private var location: GalaxySSIHealthAtlasLessonNavigation.Location { .init(entryID: entry.id, depth: depth) }
  private var search: Binding<GalaxySSIHealthAtlasLessonNavigation.Search?> {
    Binding(get: {
      state.lessonNavigation.search.flatMap { $0.origin == location && surface.contains($0.selection) ? $0 : nil }
    }, set: { if $0 == nil { state.cancelCatalogueSearch() } })
  }
  private var destination: Binding<Bool> {
    Binding(get: {
      guard let saved = state.lessonNavigation.returns[location.key] else { return false }
      return saved.structureOnly == true && surface.contains(saved.selection)
    }, set: { if !$0 { state.closeRelatedLesson(location) } })
  }
  func body(content: Content) -> some View {
    content.toolbar {
      if surface.contains(state.detailBinding(entry, depth: depth).wrappedValue), state.lessonNavigation.path.last == location {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button { state.beginCatalogueSearch(entry, depth: depth, scroll: memory.offset) } label: {
          Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
        }.accessibilityLabel(t("search")).help(t("search")).accessibilityIdentifier("atlas-open-search").disabled(depth >= 32)
      }
      }
    }
    .fullScreenCover(item: search, onDismiss: {
      if let (target, saved) = pending {
        pending = nil
        _ = state.openCatalogueResult(target, from: saved, atlas: atlas)
      } else if let offset = state.lessonReturnScroll.removeValue(forKey: location.key) {
        memory.restore(offset)
      }
    }) { saved in
      GalaxySSIHealthAtlasSearch(atlas: atlas, select: { target in
        pending = (target, saved); state.cancelCatalogueSearch()
      }, cancel: { state.cancelCatalogueSearch() })
    }
    .background(NavigationLink(isActive: destination) {
      if let saved = state.lessonNavigation.returns[location.key], let target = atlas.entry(saved.targetID) {
        GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1)
      }
    } label: { EmptyView() }.hidden())
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
