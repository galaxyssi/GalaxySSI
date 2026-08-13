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
      } else if usesGenericAgentAvatar {
        Circle()
          .fill(Color(red: 0.424, green: 0.478, blue: 0.537))
        Image(systemName: "cube.transparent")
          .foregroundColor(.white)
          .font(.system(size: max(16, size * 0.54), weight: .semibold))
        Image(systemName: "person.fill")
          .foregroundColor(.white)
          .font(.system(size: max(8, size * 0.22), weight: .bold))
          .offset(y: size * 0.06)
      } else if usesGenericCloudAvatar {
        Circle()
          .fill(Color(red: 0.357, green: 0.424, blue: 1.0))
        Image(systemName: "cloud.fill")
          .foregroundColor(Color(red: 0.478, green: 0.843, blue: 1.0))
          .font(.system(size: max(16, size * 0.54), weight: .semibold))
        Image(systemName: "arrow.up")
          .foregroundColor(.white)
          .font(.system(size: max(10, size * 0.27), weight: .bold))
          .offset(y: size * 0.08)
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

  private var usesGenericCloudAvatar: Bool {
    contact.deliveryMode == .cloudAPI && assetName == nil
  }

  private var usesGenericAgentAvatar: Bool {
    guard contact.type != "device",
          contact.deliveryMode != .cloudAPI,
          assetName == nil else {
      return false
    }
    let identity = [
      contact.id,
      contact.signalASIId,
      contact.agentKind
    ]
      .joined(separator: " ")
      .lowercased()
    return ["openclaw", "local-llm", "local-model", "custom-agent", "custom-cli"]
      .contains(where: identity.contains)
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
