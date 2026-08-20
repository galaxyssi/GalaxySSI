import SwiftUI

struct SignalASIAgentHomeHeaderView<ModelSelectionDestination: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var sessionTitle: String
  var modelStatusLabel: String
  var modelLogoLabel: String
  var brandSubtitle: String
  var voiceNavigationLabel: String
  var settingsNavigationLabel: String
  var modelSelectionDestination: ModelSelectionDestination
  var onOpenSettings: () -> Void
  var onOpenVoice: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.width < 360 || usesAccessibilityDynamicType
      let stacked = proxy.size.width < 350 || usesAccessibilityDynamicType
      let modelColumnWidth = min(
        128,
        max(88, proxy.size.width * (compact ? 0.30 : 0.36))
      )

      if stacked {
        VStack(spacing: 4) {
          HStack(spacing: 8) {
            brandButton(compact: true)
            Spacer(minLength: 8)
            settingsButton
          }
          sessionNavigation
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(spacing: compact ? 5 : 8) {
          brandButton(compact: compact)
          Spacer(minLength: compact ? 3 : 8)
          sessionNavigation
            .frame(minWidth: modelColumnWidth, maxWidth: modelColumnWidth, minHeight: 44, alignment: .trailing)
          settingsButton
        }
        .padding(.horizontal, compact ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(height: headerHeight)
    .background(Color.signalASIPageBackground)
  }

  private func brandButton(compact: Bool) -> some View {
    Button(action: onOpenVoice) {
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
      }
      .frame(minHeight: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(voiceNavigationLabel))
  }

  private var sessionNavigation: some View {
    VStack(alignment: .trailing, spacing: 2) {
      NavigationLink(destination: SignalASIConversationHubView()) {
        HStack(spacing: 4) {
          Text(sessionTitle)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .truncationMode(.tail)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(.signalASIAgentSessionTitle)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ios.agent.header.sessions")
      NavigationLink(destination: modelSelectionDestination) {
        HStack(spacing: 3) {
          Image(systemName: "chevron.left")
            .font(.system(size: 8, weight: .bold))
          SignalASIAgentRouteLogo(label: modelLogoLabel, size: 16)
          Text(modelStatusLabel)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .truncationMode(.tail)
            .minimumScaleFactor(usesAccessibilityDynamicType ? 1 : 0.72)
            .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 10, weight: .regular))
        .foregroundColor(.signalASITextSecondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ios.agent.header.model-selection")
    }
  }

  private var settingsButton: some View {
    Button(action: onOpenSettings) {
      Image(systemName: "ellipsis.horizontal")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(settingsNavigationLabel))
    .accessibilityIdentifier("ios.agent.header.settings")
  }

  private var headerHeight: CGFloat {
    if usesAccessibilityDynamicType {
      return 124
    }
    return 76
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
