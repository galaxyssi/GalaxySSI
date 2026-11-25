import SwiftUI

struct GalaxySSIHealthAtlasFunctionRelatedRow: View {
  let action: GalaxySSIHealthAtlasRelatedAction
  let selected: () -> Void
  var body: some View {
    Button(action: selected) {
      Text(action.label).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
    }.accessibilityIdentifier("atlas-related-lesson-" + action.id)
  }
}
