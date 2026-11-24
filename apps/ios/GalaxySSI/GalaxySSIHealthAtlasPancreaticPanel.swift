import SwiftUI

struct GalaxySSIHealthAtlasPancreaticPanel: View {
  let atlas: GalaxySSIHealthAtlas
  let entryID: String
  let stage: Int
  let language: String
  let open: (String) -> Void
  var showsScope = true
  var body: some View {
    if (0..<4).contains(stage) {
      if entryID == "pancreas" {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(GalaxySSIHealthAtlasPancreatic.Route.allCases) { route in
            Button { open(route.target) } label: {
              HStack(spacing: 10) {
                Image(route.asset).resizable().scaledToFit().frame(width: 72, height: 58).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                  Text(t(route.title)).font(.headline)
                  Text(t(route.chain)).font(.subheadline).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary).accessibilityHidden(true)
              }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(route.active(stage: stage) == true ? Color.green : Color.secondary.opacity(0.3)))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("atlas-pancreatic-route-" + route.id)
              .accessibilityAddTraits(route.active(stage: stage) == true ? .isSelected : [])
          }
          if showsScope { Text(t("digestive_routes_scope")).font(.footnote).foregroundColor(.secondary) }
        }.accessibilityIdentifier("atlas-pancreatic-routes")
      } else if entryID == "pancreatic-islets", let id = GalaxySSIHealthAtlasPancreatic.isletCell(stage: stage),
         let cell = atlas.entry(id), let islets = atlas.entry(entryID) {
        VStack(alignment: .leading, spacing: 8) {
          Button { open(id) } label: {
            HStack(spacing: 10) {
              if let plate = atlas.plate(for: id) {
                Image(plate.asset).resizable().scaledToFit().frame(width: 96, height: 76).accessibilityHidden(true)
              }
              VStack(alignment: .leading, spacing: 4) {
                Text(GalaxySSIHealthAtlasText.get(cell.name, language)).font(.headline)
                Text(GalaxySSIHealthAtlasText.get(atlas.model(islets).stages[stage], language)).font(.subheadline).foregroundColor(.secondary)
              }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
              Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary).accessibilityHidden(true)
            }.padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3))).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityIdentifier("atlas-islet-selected-cell")
          if showsScope { Text(t("digestive_islets_scope")).font(.footnote).foregroundColor(.secondary) }
        }.accessibilityIdentifier("atlas-islet-stages")
      }
    }
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
