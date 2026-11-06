import SwiftUI

struct GalaxySSIAgentHomeHeaderView<ModelSelectionDestination: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var sessionTitle: String
  var modelStatusLabel: String
  var brandSubtitle: String
  var newConversationLabel: String
  var settingsNavigationLabel: String
  var openWindowLabel: String
  var modelSelectionDestination: ModelSelectionDestination
  var onOpenSettings: () -> Void
  var onOpenWindow: (() -> Void)?
  var onNewConversation: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.width < 360 || usesAccessibilityDynamicType
      let stacked = proxy.size.width < 350 || usesAccessibilityDynamicType
      let modelColumnWidth = min(
        176,
        max(104, proxy.size.width * (compact ? 0.30 : 0.34))
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
    .background(Color.galaxySSIPageBackground)
  }

  private func brandButton(compact: Bool) -> some View {
    HStack(spacing: compact ? 5 : 8) {
      Button(action: { onOpenWindow?() }) {
        GalaxySSILogoView(size: headerLogoSize, cornerRadius: 8)
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .disabled(onOpenWindow == nil)
      .accessibilityLabel(Text(openWindowLabel))
      .accessibilityIdentifier("ios.agent.header.open-window")

      Button(action: onNewConversation) {
        VStack(alignment: .center, spacing: 2) {
          Text("GalaxySSI")
            .font(.system(size: compact ? 15 : 18, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
          Text(brandSubtitle)
            .font(.system(size: compact ? 10 : 12, weight: .regular))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
        }
        .frame(minWidth: 0)
      }
      .buttonStyle(.plain)
      .frame(minHeight: 44)
      .accessibilityLabel(Text(newConversationLabel))
      .accessibilityIdentifier("ios.agent.header.new-conversation")
    }
  }

  private var sessionNavigation: some View {
    VStack(alignment: .trailing, spacing: 2) {
      NavigationLink(destination: GalaxySSIConversationHubView()) {
        HStack(spacing: 4) {
          Text(sessionTitle)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .truncationMode(.tail)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: compactHeaderTypography ? 14 : 17, weight: .bold))
        .foregroundColor(.galaxySSIAgentSessionTitle)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ios.agent.header.sessions")
      NavigationLink(destination: modelSelectionDestination) {
        HStack(spacing: 3) {
          Image(systemName: "chevron.left")
            .font(.system(size: 8, weight: .bold))
          Text(modelStatusLabel)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .truncationMode(.tail)
            .minimumScaleFactor(usesAccessibilityDynamicType ? 1 : 0.72)
            .multilineTextAlignment(.trailing)
        }
        .font(.system(size: compactHeaderTypography ? 10 : 12, weight: .regular))
        .foregroundColor(.galaxySSITextSecondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("ios.agent.header.model-selection")
    }
    .contextMenu {
      if let onOpenWindow {
        Button(action: onOpenWindow) {
          Label(openWindowLabel, systemImage: "macwindow.badge.plus")
        }
      }
    }
  }

  private var settingsButton: some View {
    Button(action: onOpenSettings) {
      Image(systemName: "ellipsis.horizontal")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(settingsNavigationLabel))
    .accessibilityIdentifier("ios.agent.header.settings")
  }

  private var headerHeight: CGFloat {
    if usesAccessibilityDynamicType {
      return 108
    }
    return 72
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
      scale = 0.85
    case .small:
      scale = 0.90
    case .medium:
      scale = 0.95
    case .large:
      scale = 1.00
    case .xLarge:
      scale = 1.10
    case .xxLarge:
      scale = 1.20
    case .xxxLarge:
      scale = 1.30
    default:
      scale = 1.40
    }
    return min(56, max(36, 40 * scale))
  }

  private var compactHeaderTypography: Bool {
    dynamicTypeSize >= .xxLarge
  }
}
