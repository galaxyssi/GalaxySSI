import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasStandaloneModels: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @StateObject private var scrollMemory = GalaxySSIHealthAtlasScrollMemory()
  private var selection: Binding<GalaxySSIHealthAtlasState.Selection> { state.binding(entry) }
  private var research: Binding<Bool> {
    Binding(get: { selection.wrappedValue.researchPresented == true }, set: { if !$0 { state.closeResearch(entry) } })
  }
  var body: some View {
    VStack(spacing: 0) {
      GalaxySSIHealthAtlasCompactTabs(options: GalaxySSIHealthAtlasState.detailTabs,
        selection: Binding(get: { .function }, set: { state.closeStandaloneModel(entry, destination: $0) }),
        title: { t($0.rawValue) }, key: { $0.rawValue }, identifier: "atlas-standalone-tabs", allowsReselect: true)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          GalaxySSIHealthAtlasSimulationPanel(atlas: atlas, entry: entry, model: atlas.model(entry), simulation: selection.simulation,
            physiologyInputs: selection.physiologyInputs, previewPresented: $state.previewPresented,
            destination: { id in
              if let target = atlas.entry(id), depth < 32 {
                return AnyView(GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1))
              }
              return AnyView(EmptyView())
            })
          Button(t("research")) { state.openResearch(entry, returnScroll: scrollMemory.offset) }
            .frame(minHeight: 44).accessibilityIdentifier("atlas-open-research")
          Link(t(atlas.model(entry).reference == nil ? "evidence" : "reference_pubmed"), destination: atlas.model(entry).source)
            .frame(minHeight: 44).accessibilityIdentifier("atlas-source-physiology")
        }.padding().background {
          GalaxySSIHealthAtlasScrollAnchor(memory: scrollMemory, revision: scrollMemory.revision)
        }
      }
    }.accessibilityIdentifier("atlas-standalone-models")
      .navigationTitle(GalaxySSIHealthAtlasText.get(entry.name, language)).navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        GalaxySSIHealthAtlasAsk(atlas: atlas, entry: entry, selection: state.functionSnapshot(entry),
          selectionSnapshot: { state.functionSnapshot(entry) }, onPreviewStateChange: {
            if $0 { state.playback.pause() }
            state.previewPresented = $0
          }).padding(.horizontal)
      }
      .background(NavigationLink(isActive: research) {
        GalaxySSIHealthAtlasResearch(atlas: atlas, entry: entry, state: state, records: records, depth: depth)
      } label: { EmptyView() }.hidden())
      .background(GalaxySSIHealthAtlasRestoredDetailLink(atlas: atlas, entry: entry, state: state, records: records, depth: depth,
        enabled: selection.wrappedValue.researchPresented != true))
      .onAppear { if let offset = selection.wrappedValue.researchReturnScroll { scrollMemory.restore(offset) } }
      .onChange(of: selection.wrappedValue.researchPresented) {
        if $0 != true, let offset = selection.wrappedValue.researchReturnScroll { scrollMemory.restore(offset) }
      }
      .galaxySSIHealthTheme().environmentObject(state.playback)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
