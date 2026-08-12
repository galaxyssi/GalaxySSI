import SwiftUI

struct SignalASIAgentHomeHeaderView<ModelSelectionDestination: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var sessionTitle: String
  var modelStatusLabel: String
  var modelLogoLabel: String
  var brandSubtitle: String
  var modelSelectionDestination: ModelSelectionDestination
  var onOpenSettings: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.width < 360 || usesAccessibilityDynamicType
      let modelColumnWidth = min(
        128,
        max(88, proxy.size.width * (compact ? 0.30 : 0.36))
      )

      HStack(spacing: compact ? 5 : 8) {
        SignalASILogoView(size: headerLogoSize, cornerRadius: 8)
        VStack(alignment: .center, spacing: 2) {
          Text("SignalASI")
            .font(.system(size: compact ? 13.5 : 14.5, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
          Text(brandSubtitle)
            .font(.system(size: compact ? 9 : 10, weight: .regular))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
        }
        .frame(minWidth: 0)
        Spacer(minLength: compact ? 3 : 8)
        VStack(alignment: .trailing, spacing: 2) {
          NavigationLink(destination: SignalASIAgentSessionsView()) {
            Text(sessionTitle)
              .font(.system(size: 14, weight: .bold))
              .foregroundColor(.signalASIAgentSessionTitle)
              .lineLimit(1)
              .truncationMode(.tail)
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
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
            }
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(.signalASITextSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
          }
          .buttonStyle(.plain)
        }
        .frame(width: modelColumnWidth, minHeight: 44, alignment: .trailing)
        Button(action: onOpenSettings) {
          Image(systemName: "ellipsis.horizontal")
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, compact ? 10 : 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: usesAccessibilityDynamicType ? 88 : 76)
    .background(Color.signalASIPageBackground)
  }

  private var usesAccessibilityDynamicType: Bool {
    switch dynamicTypeSize {
    case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
      return true
    default:
      return false
    }
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
