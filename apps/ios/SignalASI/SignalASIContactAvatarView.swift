import SwiftUI

struct AvatarView: View {
  var contact: SignalASIContact
  var size: CGFloat = 42

  var body: some View {
    ZStack {
      if let assetName {
        Image(assetName)
          .resizable()
          .scaledToFill()
      } else {
        Circle()
          .fill(color)
        Image(systemName: iconName)
          .foregroundColor(.white)
          .font(.system(size: max(14, size * 0.43), weight: .semibold))
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }

  private var assetName: String? {
    let identityFields = [
      contact.id,
      contact.signalASIId,
      contact.name,
      contact.displayName,
      contact.type
    ]

    if let agentAssetName = SignalASIAgentAvatarAssetCatalog.assetName(for: identityFields) {
      return agentAssetName
    }

    let identity = identityFields.joined(separator: " ").lowercased()
    if contact.deliveryMode.isSignalASILinkFamily || identity.contains("signalasi") {
      return "SignalASILogo"
    }
    return nil
  }

  private var iconName: String {
    switch contact.deliveryMode {
    case .cloudAPI: return "cloud"
    case .link, .pcConnector: return "desktopcomputer"
    case .local: return "gearshape"
    }
  }

  private var color: Color {
    switch contact.deliveryMode {
    case .cloudAPI: return .purple
    case .link, .pcConnector: return .green
    case .local: return .gray
    }
  }
}
