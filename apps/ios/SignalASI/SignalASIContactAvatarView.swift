import CryptoKit
import SwiftUI

struct AvatarView: View {
  var contact: SignalASIContact
  var size: CGFloat = 42

  var body: some View {
    ZStack {
      if usesIdentityIdenticon {
        SignalASIIdenticonView(
          pattern: SignalASIIdenticon.fromIdentityFingerprint(contact.identityFingerprint)
        )
      } else if let assetName {
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

  private var usesIdentityIdenticon: Bool {
    contact.type.caseInsensitiveCompare("person") == .orderedSame &&
      contact.identityFingerprint.count == 64
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

struct SignalASIIdenticonPattern: Equatable {
  static let gridSize = 5
  var cells: [Bool]
  var colorIndex: Int

  init(cells: [Bool], colorIndex: Int) {
    precondition(cells.count == Self.gridSize * Self.gridSize)
    self.cells = cells
    self.colorIndex = colorIndex
  }

  var color: Color {
    SignalASIIdenticon.color(at: colorIndex)
  }

  func isFilled(row: Int, column: Int) -> Bool {
    cells[row * Self.gridSize + column]
  }
}

enum SignalASIIdenticon {
  private static let palette: [Color] = [
    Color(red: 212 / 255, green: 190 / 255, blue: 40 / 255),
    Color(red: 47 / 255, green: 129 / 255, blue: 247 / 255),
    Color(red: 31 / 255, green: 157 / 255, blue: 120 / 255),
    Color(red: 224 / 255, green: 82 / 255, blue: 82 / 255),
    Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255),
    Color(red: 219 / 255, green: 124 / 255, blue: 38 / 255),
    Color(red: 22 / 255, green: 125 / 255, blue: 154 / 255),
    Color(red: 180 / 255, green: 66 / 255, blue: 140 / 255)
  ]

  static func color(at index: Int) -> Color {
    palette[max(0, index) % palette.count]
  }

  static func fromIdentityFingerprint(_ fingerprint: String) -> SignalASIIdenticonPattern {
    let normalized = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .ifBlank("signalasi-local-identity")
    let digest = Array(SHA256.hash(data: Data(normalized.utf8)))
    var cells = [Bool](repeating: false, count: SignalASIIdenticonPattern.gridSize * SignalASIIdenticonPattern.gridSize)
    for row in 0..<SignalASIIdenticonPattern.gridSize {
      for sourceColumn in 0...2 {
        let sourceIndex = row * 3 + sourceColumn
        let filled = digest[sourceIndex / 8] & (1 << (sourceIndex % 8)) != 0
        cells[row * SignalASIIdenticonPattern.gridSize + sourceColumn] = filled
        cells[row * SignalASIIdenticonPattern.gridSize + (4 - sourceColumn)] = filled
      }
    }
    return SignalASIIdenticonPattern(
      cells: cells,
      colorIndex: Int(digest[2]) % palette.count
    )
  }
}

struct SignalASIIdenticonView: View {
  var pattern: SignalASIIdenticonPattern

  var body: some View {
    Canvas { context, size in
      let side = min(size.width, size.height)
      guard side > 0 else { return }
      let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
      let bounds = CGRect(origin: origin, size: CGSize(width: side, height: side))
      context.fill(
        Path(ellipseIn: bounds),
        with: .color(Color(red: 246 / 255, green: 248 / 255, blue: 250 / 255))
      )
      let gridInset = side * 0.12
      let cellSize = (side - gridInset * 2) / CGFloat(SignalASIIdenticonPattern.gridSize)
      for row in 0..<SignalASIIdenticonPattern.gridSize {
        for column in 0..<SignalASIIdenticonPattern.gridSize where pattern.isFilled(row: row, column: column) {
          let rect = CGRect(
            x: origin.x + gridInset + CGFloat(column) * cellSize,
            y: origin.y + gridInset + CGFloat(row) * cellSize,
            width: cellSize,
            height: cellSize
          )
          context.fill(Path(rect), with: .color(pattern.color))
        }
      }
    }
    .clipShape(Circle())
    .overlay(
      Circle()
        .stroke(
          Color(red: 208 / 255, green: 215 / 255, blue: 222 / 255),
          lineWidth: 1
        )
    )
  }
}
