import SwiftUI

struct GalaxySSIHealthAtlasSceneFrame<Content: View>: View {
  let identifier: String
  let inset: CGFloat
  let ground: Color?
  let content: () -> Content
  init(identifier: String, inset: CGFloat = 0, ground: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.identifier = identifier; self.inset = inset; self.ground = ground; self.content = content
  }
  var body: some View {
    content().padding(inset).frame(maxWidth: .infinity, alignment: .leading)
      .background(ground ?? Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
      .accessibilityIdentifier(identifier)
  }
}

struct GalaxySSIHealthAtlasReservedCaption: View {
  let values: [String]
  let selected: Int
  let identifier: String
  var maximumLines: Int? = nil
  var body: some View {
    if !values.isEmpty {
      ZStack(alignment: .topLeading) {
        // Reserve the longest wrapped chapter at the current width and Dynamic Type size.
        ForEach(values.indices, id: \.self) { index in
          Text(values[index]).lineLimit(maximumLines).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            .hidden().accessibilityHidden(true).allowsHitTesting(false)
        }
        Text(values[min(values.count - 1, max(0, selected))]).lineLimit(maximumLines).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier(identifier)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
