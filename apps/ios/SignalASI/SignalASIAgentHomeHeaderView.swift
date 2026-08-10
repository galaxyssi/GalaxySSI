import SwiftUI

struct SignalASIAgentHomeHeaderView<ModelSelectionDestination: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var sessionTitle: String
  var modelStatusLabel: String
  var modelLogoLabel: String
  var brandSubtitle: String
  var modelSelectionDestination: ModelSelectionDestination

  var body: some View {
    HStack(spacing: 8) {
      SignalASILogoView(size: headerLogoSize, cornerRadius: 8)
      VStack(alignment: .center, spacing: 2) {
        Text("SignalASI")
          .font(.system(size: 14.5, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
        Text(brandSubtitle)
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        NavigationLink(destination: SignalASIAgentSessionsView()) {
          Text(sessionTitle)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.signalASIAgentSessionTitle)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
        NavigationLink(destination: modelSelectionDestination) {
          HStack(spacing: 3) {
            Image(systemName: "chevron.down")
              .font(.system(size: 8, weight: .bold))
            SignalASIAgentRouteLogo(label: modelLogoLabel, size: 16)
            Text(modelStatusLabel)
              .lineLimit(1)
              .minimumScaleFactor(0.72)
          }
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
      }
      .frame(width: 128, minHeight: 44, alignment: .trailing)
      NavigationLink(destination: SettingsView()) {
        Image(systemName: "ellipsis.horizontal")
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(height: 76)
    .background(Color.signalASIPageBackground)
  }

  private var headerLogoSize: CGFloat {
    let scale: CGFloat
    switch dynamicTypeSize {
    case .xSmall:
      scale = 0.82
    case .small:
      scale = 0.90
    case .medium:
      scale = 1.00
    case .large:
      scale = 1.10
    case .xLarge:
      scale = 1.20
    case .xxLarge:
      scale = 1.30
    case .xxxLarge:
      scale = 1.40
    default:
      scale = 1.45
    }
    return min(56, max(32, 39 * scale))
  }
}
