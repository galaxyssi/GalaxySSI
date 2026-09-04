import SwiftUI

struct GalaxySSIContactKindPresentation {
  var title: String
  var systemImage: String
  var foreground: Color
  var background: Color
  var stroke: Color

  static func forContact(
    _ contact: GalaxySSIContact,
    t: (String, String) -> String
  ) -> GalaxySSIContactKindPresentation? {
    if contact.id == "system" || contact.id == "me" || contact.id.hasPrefix("group:") {
      return nil
    }
    return presentation(
      id: contact.id,
      type: contact.type,
      agentKind: contact.agentKind,
      deliveryMode: contact.deliveryMode.rawValue,
      t: t
    )
  }

  static func forRequest(
    _ request: GalaxySSIFriendRequest,
    t: (String, String) -> String
  ) -> GalaxySSIContactKindPresentation? {
    presentation(
      id: request.galaxySSIId,
      type: request.type,
      agentKind: request.agentKind,
      deliveryMode: "",
      t: t
    )
  }

  private static func presentation(
    id: String,
    type: String,
    agentKind: String,
    deliveryMode: String,
    t: (String, String) -> String
  ) -> GalaxySSIContactKindPresentation? {
    let cleanId = id.lowercased()
    let agentId = agentIdFromContactId(cleanId)
    let cleanType = type.lowercased()
    let cleanKind = agentKind.lowercased()
    let cleanDelivery = deliveryMode.lowercased()

    if cleanId.hasPrefix("cloud:") ||
        cleanDelivery == "cloud_api" ||
        cleanDelivery == "cloudapi" ||
        cleanKind == "cloud-api" ||
        cleanKind == "cloud-model" ||
        cleanKind == "local-model" {
      return model(t: t)
    }
    if cleanType == "device" ||
        cleanKind == "device" ||
        agentId == "pc_agent" ||
        agentId == "home_hub" ||
        agentId.contains("device") ||
        agentId.contains("hub") {
      return device(t: t)
    }
    if cleanType == "agent" ||
        cleanType == "hermes" ||
        cleanKind == "local-cli" ||
        cleanKind == "custom-cli" ||
        cleanKind == "desktop-agent" ||
        cleanKind == "contact-agent" ||
        agentId == "hermes" ||
        agentId.hasSuffix("-agent") ||
        agentId.contains("_agent") {
      return agent(t: t)
    }
    return nil
  }

  private static func model(t: (String, String) -> String) -> GalaxySSIContactKindPresentation {
    GalaxySSIContactKindPresentation(
      title: t("contact_tag_model", "Model"),
      systemImage: "cpu",
      foreground: color(0x4E6BFF),
      background: color(0xEEF2FF),
      stroke: color(0x9FB0FF)
    )
  }

  private static func device(t: (String, String) -> String) -> GalaxySSIContactKindPresentation {
    GalaxySSIContactKindPresentation(
      title: t("contact_tag_device", "Device"),
      systemImage: "desktopcomputer",
      foreground: color(0x2F80ED),
      background: color(0xEEF6FF),
      stroke: color(0x9DCAFF)
    )
  }

  private static func agent(t: (String, String) -> String) -> GalaxySSIContactKindPresentation {
    GalaxySSIContactKindPresentation(
      title: t("contact_tag_agent", "Agent"),
      systemImage: "sparkles",
      foreground: color(0x10A65A),
      background: color(0xEEFFF6),
      stroke: color(0x8BE2B5)
    )
  }

  private static func agentIdFromContactId(_ id: String) -> String {
    id.split(separator: ":").last.map(String.init) ?? id
  }

  private static func color(_ rgb: UInt32) -> Color {
    Color(
      red: Double((rgb >> 16) & 0xFF) / 255.0,
      green: Double((rgb >> 8) & 0xFF) / 255.0,
      blue: Double(rgb & 0xFF) / 255.0
    )
  }
}

struct GalaxySSIContactKindBadge: View {
  var presentation: GalaxySSIContactKindPresentation

  var body: some View {
    Text(presentation.title)
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundColor(presentation.foreground)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 6)
      .frame(minHeight: 20)
      .background(presentation.background)
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(presentation.stroke, lineWidth: 0.7)
      )
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      .accessibilityLabel(Text(presentation.title))
  }
}
