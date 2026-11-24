import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasSearch: View {
  let atlas: GalaxySSIHealthAtlas
  let select: (String) -> Void
  let cancel: () -> Void
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var query = ""
  @State private var kind = "organ"
  @State private var system = ""
  @State private var tissues = false
  @State private var limit = 24
  @FocusState private var focused: Bool
  var body: some View {
    NavigationView {
      List {
        Picker(t("whole"), selection: $kind) {
          Text(t("systems")).tag("system")
          Text(t("organs")).tag("organ")
          Text(t("cells")).tag("cell")
        }.pickerStyle(.segmented)
        if kind == "organ" {
          Picker(t("organs"), selection: $tissues) {
            Text(t("organs")).tag(false)
            Text(t("tissues")).tag(true)
          }.pickerStyle(.segmented).accessibilityIdentifier("atlas-search-layer")
        }
        TextField(t("search"), text: $query).focused($focused)
          .accessibilityIdentifier("atlas-search-query")
        if kind != "system" {
          Picker(t("systems"), selection: $system) {
            Text(t("all")).tag("")
            ForEach(atlas.entries.filter { $0.kind == .system }) { entry in
              Text(GalaxySSIHealthAtlasText.get(entry.name, language)).tag(entry.id)
            }
          }
        }
        let matches = atlas.search(query, kind: kind == "organ" && tissues ? .tissue : GalaxySSIHealthAtlas.Kind(rawValue: kind),
          system: system, language: language)
        if matches.isEmpty { Text(t("no_matches")) }
        ForEach(Array(matches.prefix(limit))) { entry in
          Button { focused = false; select(entry.id) } label: { GalaxySSIHealthAtlasRow(entry: entry) }
            .buttonStyle(.plain).accessibilityIdentifier("atlas-search-result-" + entry.id)
        }
        if matches.count > limit { Button(t("more")) { limit += 24 } }
      }
      .navigationTitle(t("search")).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { focused = false; cancel() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
            .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))
        }
      }
      .onAppear { focused = true }
      .onChange(of: query) { value in if value.count > 100 { query = String(value.prefix(100)) }; limit = 24 }
      .onChange(of: kind) { _ in system = ""; tissues = false; limit = 24 }
      .onChange(of: tissues) { _ in limit = 24 }
      .onChange(of: system) { _ in limit = 24 }
    }.navigationViewStyle(.stack).galaxySSIHealthTheme()
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
