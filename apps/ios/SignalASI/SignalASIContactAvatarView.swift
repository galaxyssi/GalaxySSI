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
    if contact.type == "device" {
      return nil
    }
    let identityFields = [
      contact.id,
      contact.signalASIId,
      contact.name,
      contact.displayName,
      contact.type,
      contact.agentKind,
      contact.cloudProvider,
      contact.selectedCloudModel?.provider ?? "",
      contact.selectedCloudModel?.modelId ?? ""
    ]

    if contact.deliveryMode == .cloudAPI {
      if let providerAssetName = SignalASIAgentAvatarAssetCatalog.cloudProviderAssetName(for: identityFields) {
        return providerAssetName
      }
    } else if let agentAssetName = SignalASIAgentAvatarAssetCatalog.assetName(for: identityFields) {
      return agentAssetName
    }

    let identity = identityFields.joined(separator: " ").lowercased()
    if contact.deliveryMode.isSignalASILinkFamily || identity.contains("signalasi") {
      return "SignalASILogo"
    }
    return nil
  }

  private var iconName: String {
    if contact.type == "device" {
      let deviceIdentity = [
        contact.devicePlatform ?? "",
        contact.deviceModel ?? "",
        contact.deviceProfileName ?? ""
      ].joined(separator: " ").lowercased()
      if deviceIdentity.contains("mac") || deviceIdentity.contains("desktop") || deviceIdentity.contains("windows") {
        return "desktopcomputer"
      }
      if deviceIdentity.contains("ipad") || deviceIdentity.contains("tablet") {
        return "ipad"
      }
      return "iphone"
    }
    if contact.agentKind == "local-model" || contact.deliveryMode == .local {
      return "memorychip"
    }
    switch contact.deliveryMode {
    case .cloudAPI: return "cloud.fill"
    case .link, .pcConnector: return "desktopcomputer"
    case .local: return "memorychip"
    }
  }

  private var color: Color {
    if contact.type == "device" {
      return .blue
    }
    switch contact.deliveryMode {
    case .cloudAPI: return .purple
    case .link, .pcConnector: return .green
    case .local: return .gray
    }
  }
}
