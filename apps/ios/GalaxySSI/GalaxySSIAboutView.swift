import SwiftUI
import UIKit

struct GalaxySSIAboutView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  private var versionName: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      return "0.1.0"
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "0.1.0" : trimmed
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("settings_about_galaxyssi", "About GalaxySSI"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          productSection
          trustSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var productSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("about_section_product", "Product"))
      GalaxySSIAboutVersionRow(
        title: t("about_version", "Version"),
        subtitle: t("about_version_subtitle", "GalaxySSI iOS release"),
        value: "v\(versionName)"
      )
      GalaxySSISecurityNavigationRow(
        title: t("settings_signal_link_protocol", "Signal Link Protocol        v1.0.3"),
        subtitle: t("about_protocol_subtitle", "Secure communication and agent interoperability protocol"),
        systemImage: "link",
        tint: .blue,
        badge: "v1.0.3"
      ) {
        GalaxySSILinkProtocolView()
      }
    }
  }

  private var trustSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("about_section_trust", "Trust and transparency"))
      GalaxySSISecurityNavigationRow(
        title: t("about_security", "Security and privacy"),
        subtitle: t("about_security_subtitle", "Local identity, encrypted trust, and user-controlled data"),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: t("common_view", "View")
      ) {
        GalaxySSISecurityCenterView()
      }
      GalaxySSISecurityActionRow(
        title: t("about_open_source", "Open source"),
        subtitle: t("about_open_source_subtitle", "Source code and Apache License 2.0"),
        systemImage: "chevron.left.forwardslash.chevron.right",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        openSourceRepository()
      }
    }
  }

  private func openSourceRepository() {
    guard let url = URL(string: "https://github.com/galaxyssi/GalaxySSI") else { return }
    UIApplication.shared.open(url)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIAboutVersionRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var title: String
  var subtitle: String
  var value: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "info.circle")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.blue)
        .frame(width: 42, height: 42)
        .background(Color.blue.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          labels
          version
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        HStack(alignment: .top, spacing: 12) {
          labels.frame(maxWidth: .infinity, alignment: .leading)
          version.frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var labels: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundColor(.galaxySSITextPrimary)
      Text(subtitle)
        .font(.footnote)
        .foregroundColor(.galaxySSITextSecondary)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var version: some View {
    Text(value)
      .font(.body)
      .foregroundColor(.blue)
      .lineLimit(nil)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
  }
}
