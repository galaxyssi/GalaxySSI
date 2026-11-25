import SwiftUI

struct GalaxySSIHealthAtlasSimulationPlate: View {
  let plate: GalaxySSIHealthAtlas.Plate
  let name: String
  let language: String
  let preview: (Bool) -> Void
  @State private var presented = false
  @State private var zoom: Double = 1
  var body: some View {
    Button { zoom = 1; preview(true); presented = true } label: {
      Image(plate.asset).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 280)
    }.buttonStyle(.plain).accessibilityLabel(name).accessibilityIdentifier("atlas-simulation-art")
      .sheet(isPresented: $presented, onDismiss: { preview(false) }) {
        NavigationView {
          VStack {
            GalaxySSIHealthAtlasLabeledArtwork(asset: plate.asset, aspectRatio: plate.aspectRatio, zoom: $zoom,
              currentID: nil, spots: [], labels: [], onSelect: { _ in })
            Slider(value: $zoom, in: 1...4).accessibilityLabel(GalaxySSIHealthBodyText.string("zoom", language: language))
          }.padding().navigationTitle(name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button { presented = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                  .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.cancel", fallback: "Cancel", language: language))
              }
            }
        }.navigationViewStyle(.stack)
      }
  }
}
