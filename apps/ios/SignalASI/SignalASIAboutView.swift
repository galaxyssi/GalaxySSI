import SwiftUI
import UIKit

struct SignalASIAboutView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  private var versionName: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      return "0.1.0"
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "0.1.0" : trimmed
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("settings_about_signalasi", "About SignalASI"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASIAboutHeroView(
            title: "SignalASI",
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var productSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("about_section_product", "Product"))
      SignalASISecurityStatusRow(
        title: t("about_version", "Version"),
        subtitle: t("about_version_subtitle", "SignalASI iOS release"),
        systemImage: "info.circle",
        tint: .blue,
        badge: "v\(versionName)"
      )
      SignalASISecurityNavigationRow(
        title: t("settings_signal_link_protocol", "Signal Link Protocol        v1.0.3"),
        subtitle: t("about_protocol_subtitle", "Secure communication and agent interoperability protocol"),
        systemImage: "link",
        tint: .blue,
        badge: "v1.0.3"
      ) {
        SignalASILinkProtocolView()
      }
    }
  }

  private var trustSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("about_section_trust", "Trust and transparency"))
      SignalASISecurityNavigationRow(
        title: t("about_security", "Security and privacy"),
        subtitle: t("about_security_subtitle", "Local identity, encrypted trust, and user-controlled data"),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: t("common_view", "View")
      ) {
        SignalASISecurityCenterView()
      }
      SignalASISecurityActionRow(
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
    guard let url = URL(string: "https://github.com/signalasi/SignalASI") else { return }
    UIApplication.shared.open(url)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIAboutHeroView: View {
  var title: String
  var subtitle: String
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      SignalASILogoView(size: 56, cornerRadius: 10)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.signalASIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.signalASIAccent.opacity(0.12))
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
