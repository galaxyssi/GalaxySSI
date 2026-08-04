import SwiftUI

struct SignalASITextSizeSettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  private var selectedMode: AppTextScaleMode {
    store.displaySettings.textScale
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_text_size_title", "Text Size"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("cc_text_size_preview_title", "Readable by design"),
            subtitle: t(
              "cc_text_size_preview_subtitle",
              "Changes apply immediately across SignalASI and remain after restart."
            ),
            systemImage: "textformat.size",
            tint: .signalASIAccent,
            badge: textScaleLabel(selectedMode)
          )
          scaleSection
          previewSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var scaleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_text_size_section", "Text scale"))
      ForEach(AppTextScaleMode.allCases) { mode in
        SignalASISecurityActionRow(
          title: textScaleLabel(mode),
          subtitle: textScaleDescription(mode),
          systemImage: mode == selectedMode ? "checkmark.circle" : "textformat.size",
          tint: mode == selectedMode ? .signalASIAccent : .gray,
          badge: mode == selectedMode ? t("settings_language_selected", "Selected") : "",
          action: {
            select(mode)
          }
        )
      }
    }
  }

  private var previewSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_text_size_preview_section", "Preview"))
      SignalASITextSizePreviewCard(
        title: t("cc_text_size_preview_sample_title", "SignalASI can understand and act"),
        subtitle: t(
          "cc_text_size_preview_sample_subtitle",
          "This preview uses the same title and supporting text hierarchy as the Control Center."
        ),
        badge: textScaleLabel(selectedMode),
        chips: [
          t("cc_text_size_preview_chip_agent", "Agent"),
          t("cc_text_size_preview_chip_action", "Action"),
          t("cc_text_size_preview_chip_ready", "Ready")
        ],
        scale: previewScale(selectedMode)
      )
    }
  }

  private func select(_ mode: AppTextScaleMode) {
    guard mode != selectedMode else { return }
    store.updateDisplaySettings { settings in
      settings.textScale = mode
    }
  }

  private func textScaleLabel(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system", "Follow system")
    case .standard:
      return t("cc_text_size_standard", "Standard")
    case .comfortable:
      return t("cc_text_size_comfortable", "Comfortable")
    case .large:
      return t("cc_text_size_large", "Large")
    case .extraLarge:
      return t("cc_text_size_extra_large", "Extra large")
    }
  }

  private func textScaleDescription(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system_subtitle", "Use the iOS text-size preference")
    case .standard:
      return t("cc_text_size_standard_subtitle", "100% - More content on screen")
    case .comfortable:
      return t("cc_text_size_comfortable_subtitle", "110% - Recommended")
    case .large:
      return t("cc_text_size_large_subtitle", "120% - Easier to read")
    case .extraLarge:
      return t("cc_text_size_extra_large_subtitle", "132% - Maximum readability")
    }
  }

  private func previewScale(_ mode: AppTextScaleMode) -> CGFloat {
    switch mode {
    case .system:
      return 1.0
    case .standard:
      return 1.0
    case .comfortable:
      return 1.10
    case .large:
      return 1.20
    case .extraLarge:
      return 1.32
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASITextSizePreviewCard: View {
  var title: String
  var subtitle: String
  var badge: String
  var chips: [String]
  var scale: CGFloat

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.signalASIAccent.opacity(0.16))
        Image(systemName: "sparkles")
          .font(.system(size: 20 * scale, weight: .semibold))
          .foregroundColor(.signalASIAccent)
      }
      .frame(width: 46, height: 46)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 16 * scale, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
          Spacer(minLength: 0)
          Text(badge)
            .font(.system(size: 11 * scale, weight: .semibold))
            .foregroundColor(.signalASIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(Color.signalASIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 12 * scale))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
          ForEach(chips, id: \.self) { chip in
            previewChip(chip)
          }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func previewChip(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11 * scale, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .frame(minHeight: 24)
      .background(Color.signalASIButtonSoft)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
