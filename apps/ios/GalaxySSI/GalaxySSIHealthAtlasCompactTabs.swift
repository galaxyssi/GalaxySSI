import SwiftUI

struct GalaxySSIHealthAtlasCompactTabs<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option
  let title: (Option) -> String
  let key: (Option) -> String
  let identifier: String
  @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 14
  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(options, id: \.self) { option in
        Button { selection = option } label: {
          VStack(spacing: 0) {
            ZStack {
              ForEach(options, id: \.self) { candidate in
                Text(title(candidate)).fixedSize(horizontal: false, vertical: true)
                  .hidden().accessibilityHidden(true)
              }
              Text(title(option)).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 42)
            Rectangle().fill(selection == option ? GalaxySSIHealthTheme.accent : Color.clear)
              .frame(height: 2).padding(.horizontal, 24)
          }.contentShape(Rectangle())
        }.buttonStyle(.plain).font(.system(size: size, weight: selection == option ? .semibold : .regular))
          .foregroundColor(selection == option ? GalaxySSIHealthTheme.accent : .secondary)
          .accessibilityAddTraits(selection == option ? .isSelected : [])
          .accessibilityIdentifier(identifier + "-" + key(option))
      }
    }.accessibilityIdentifier(identifier)
  }
}
