import Foundation
import SwiftUI

enum SignalASISecurityFormatter {
  static func fingerprint(_ value: String, unknown: String) -> String {
    let cleaned = value.filter { $0.isLetter || $0.isNumber }
    let limited = String(cleaned.prefix(64))
    guard !limited.isEmpty else { return unknown }
    return chunk(limited, into: 32).joined(separator: "\n")
  }

  static func time(_ date: Date, unknown: String, language: String = LanguagePolicySettings.auto) -> String {
    guard date.timeIntervalSince1970 > 1 else { return unknown }
    let formatter = DateFormatter()
    formatter.locale = SignalASILocalization.dateLocale(language: language)
    formatter.dateFormat = "MM/dd HH:mm"
    return formatter.string(from: date)
  }

  static func securityStatusLabel(_ status: String, language: String) -> String {
    let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "ready", "verified", "paired", "ok":
      return SignalASILocalization.string("signalasi.status.ready", fallback: "Ready", language: language)
    case "pairing", "pending":
      return SignalASILocalization.string("signalasi.security_center.status_pending", fallback: "Pending", language: language)
    case "needs_setup", "needs_pairing", "unverified":
      return SignalASILocalization.string("signalasi.status.needs_setup", fallback: "Needs Setup", language: language)
    case "deleted", "revoked":
      return SignalASILocalization.string("signalasi.security_center.status_revoked", fallback: "Revoked", language: language)
    case "":
      return SignalASILocalization.string("signalasi.status.unknown", fallback: "Unknown", language: language)
    default:
      return status
    }
  }

  static func agentSystemImage(id: String, kind: String) -> String {
    let identity = "\(id) \(kind)".lowercased()
    if identity.contains("codex") { return "terminal" }
    if identity.contains("claude") { return "chevron.left.forwardslash.chevron.right" }
    if identity.contains("llm") || identity.contains("model") { return "cpu" }
    if identity.contains("browser") || identity.contains("web") { return "globe" }
    if identity.contains("file") { return "folder" }
    return "person.circle"
  }

  private static func chunk(_ value: String, into size: Int) -> [String] {
    var result: [String] = []
    var index = value.startIndex
    while index < value.endIndex {
      let next = value.index(index, offsetBy: size, limitedBy: value.endIndex) ?? value.endIndex
      result.append(String(value[index..<next]))
      index = next
    }
    return result
  }
}

struct SignalASISecurityHeroView: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 54, height: 54)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

struct SignalASISecuritySectionTitle: View {
  var title: String

  var body: some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }
}

struct SignalASISecurityNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    monospacedSubtitle: Bool = false,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.monospacedSubtitle = monospacedSubtitle
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      SignalASISecurityRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: monospacedSubtitle,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

struct SignalASISecurityActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImage: String? = nil
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      SignalASISecurityRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        assetImage: assetImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: monospacedSubtitle,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

struct SignalASISecurityStatusRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool = false

  var body: some View {
    SignalASISecurityRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      monospacedSubtitle: monospacedSubtitle,
      showsDisclosure: false
    )
  }
}

struct SignalASISecurityPrimaryButton: View {
  var title: String
  var systemImage: String
  var tint: Color
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 16, weight: .semibold))
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(tint)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

struct SignalASISecurityRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImage: String? = nil
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        if let assetImage, !assetImage.isEmpty {
          Image(assetImage)
            .resizable()
            .scaledToFit()
            .frame(width: 29, height: 29)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
        }
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(monospacedSubtitle ? .system(size: 12, design: .monospaced) : .system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(monospacedSubtitle ? 3 : 2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
