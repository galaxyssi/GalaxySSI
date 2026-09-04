import SwiftUI

struct GalaxySSIRoutingPolicyView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_route_by_task_title", "Route by Task Type"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("cc_routing_policy_banner_title", "Intent-aware routing"),
            subtitle: t(
              "cc_routing_policy_banner_subtitle",
              "GalaxySSI derives the mode from each request and the live health of configured resources."
            ),
            systemImage: "slider.horizontal.3",
            tint: .blue,
            badge: t("cc_status_automatic", "Automatic")
          )
          GalaxySSISecuritySectionTitle(title: t("cc_section_current_strategy", "Current Strategy"))
          VStack(spacing: 8) {
            policyRow(
              title: t("cc_routing_balanced_title", "Balanced"),
              subtitle: t("cc_routing_balanced_subtitle", "Default scoring across quality, latency, cost, privacy, and availability"),
              systemImage: "speedometer",
              tint: .blue
            )
            policyRow(
              title: t("cc_routing_fast_title", "Fast"),
              subtitle: t("cc_routing_fast_subtitle", "Prefer phone and low-latency local resources"),
              systemImage: "bolt.fill",
              tint: .galaxySSIAccent
            )
            policyRow(
              title: t("cc_routing_economy_title", "Economy"),
              subtitle: t("cc_routing_economy_subtitle", "Prefer free local resources before paid cloud models"),
              systemImage: "leaf.fill",
              tint: .orange
            )
            policyRow(
              title: t("cc_routing_quality_title", "Highest quality"),
              subtitle: t("cc_routing_quality_subtitle", "Prefer frontier models and strong reasoning resources"),
              systemImage: "star.fill",
              tint: .purple
            )
            policyRow(
              title: t("cc_routing_private_title", "Private"),
              subtitle: t("cc_routing_private_subtitle", "Exclude cloud resources and keep execution on trusted local devices"),
              systemImage: "lock.fill",
              tint: .galaxySSITextSecondary
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func policyRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
    GalaxySSISecurityStatusRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: ""
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
