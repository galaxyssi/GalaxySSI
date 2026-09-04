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
          GalaxySSIAboutHeroView(
            title: "GalaxySSI",
            subtitle: t(
              "about_product_subtitle",
              "A secure superintelligent agent for people, agents, models, and devices"
            ),
            badge: "v\(versionName)"
          )
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
      GalaxySSISecurityStatusRow(
        title: t("about_version", "Version"),
        subtitle: t("about_version_subtitle", "GalaxySSI iOS release"),
        systemImage: "info.circle",
        tint: .blue,
        badge: "v\(versionName)"
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

private struct GalaxySSIAboutHeroView: View {
  var title: String
  var subtitle: String
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      GalaxySSILogoView(size: 56, cornerRadius: 10)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.galaxySSIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}
