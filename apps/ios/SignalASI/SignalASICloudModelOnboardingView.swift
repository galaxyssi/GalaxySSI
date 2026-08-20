import SwiftUI
import UIKit

struct CloudModelProviderSelectionView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var onModelAdded: ((SignalASIContact) -> Void)? = nil

  private var providers: [String] {
    CloudModelPreset.androidParity.reduce(into: [String]()) { result, preset in
      if !result.contains(preset.provider) {
        result.append(preset.provider)
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.cloud.models_title", "Cloud Models"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CloudModelHeroView(
            title: t("signalasi.cloud.select_provider", "Select Provider"),
            subtitle: t(
              "signalasi.cloud.provider_hero_subtitle",
              "Each cloud model is saved as an independent contact. Multiple providers and models can coexist."
            ),
            systemImage: "cloud.fill",
            tint: .signalASIInsightText,
            badge: t("signalasi.cloud.direct", "Direct")
          )
          sectionTitle("Provider")
          VStack(spacing: 8) {
            ForEach(providers, id: \.self) { provider in
              CloudModelNavigationRow(
                title: provider,
                subtitle: providerSubtitle(provider),
                systemImage: "cloud.fill",
                assetImageName: providerLogoAssetName(provider),
                tint: providerTint(provider),
                badge: providerCount(provider)
              ) {
                CloudModelPickerView(provider: provider, onModelAdded: onModelAdded)
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func providerCount(_ provider: String) -> String {
    String(
      format: t("signalasi.cloud.provider_count", "%d"),
      CloudModelPreset.androidParity.filter { $0.provider == provider }.count
    )
  }

  private func providerSubtitle(_ provider: String) -> String {
    switch provider {
    case "OpenAI":
      return t("signalasi.cloud.provider.openai.subtitle", "GPT-5.5, GPT-5.4 mini/nano, and other OpenAI API models")
    case "Anthropic":
      return t("signalasi.cloud.provider.anthropic.subtitle", "Claude Opus, Sonnet, Haiku; uses Messages API")
    case "Google Gemini":
      return t("signalasi.cloud.provider.gemini.subtitle", "Gemini Pro / Flash / Flash Lite; direct Google API from the phone")
    case "DeepSeek":
      return t("signalasi.cloud.provider.deepseek.subtitle", "DeepSeek V4 Pro, V4 Flash")
    case "Qwen":
      return t("signalasi.cloud.provider.qwen.subtitle", "Qwen 3.7 Max/Plus, Qwen 3.6 Flash; DashScope OpenAI compatible")
    case "OpenRouter":
      return t("signalasi.cloud.provider.openrouter.subtitle", "Unified access to multiple cloud models with custom routing")
    default:
      return t("signalasi.cloud.provider.custom.subtitle", "OpenAI-compatible custom endpoint")
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct CloudModelPickerView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var provider: String
  var onModelAdded: ((SignalASIContact) -> Void)? = nil

  private var presets: [CloudModelPreset] {
    CloudModelPreset.androidParity.filter { $0.provider == provider }
  }

  private var rows: [CloudModelPreset] {
    if provider == "Custom" {
      return presets
    }
    guard let base = presets.first else {
      return presets
    }
    return presets + [
      CloudModelPreset(
        provider: provider,
        name: t("signalasi.cloud.custom_model_id", "Custom Model ID"),
        modelId: "model-id",
        endpoint: base.endpoint,
        apiStyle: base.apiStyle
      )
    ]
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: provider,
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CloudModelHeroView(
            title: provider,
            subtitle: providerSubtitle,
            systemImage: "cloud.fill",
            assetImageName: providerLogoAssetName(provider),
            tint: providerTint(provider),
            badge: t("signalasi.cloud.select_model", "Select Model")
          )
          sectionTitle(t("signalasi.cloud.section_model", "Model"))
          VStack(spacing: 8) {
            ForEach(rows) { preset in
              CloudModelNavigationRow(
                title: preset.name,
                subtitle: subtitle(for: preset),
                systemImage: preset.modelId == "model-id" ? "square.and.pencil" : "link",
                tint: providerTint(provider),
                badge: t("signalasi.common.select", "Select")
              ) {
                CloudModelConfigurationView(preset: preset, onModelAdded: onModelAdded)
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var providerSubtitle: String {
    CloudModelOnboardingCopy.providerSubtitle(provider, language: interfaceLanguage)
  }

  private func subtitle(for preset: CloudModelPreset) -> String {
    if preset.modelId == "model-id" && provider != "Custom" {
      return String(
        format: t("signalasi.cloud.custom_model_subtitle", "Use another or newly released model from %@"),
        provider
      )
    }
    return preset.modelId
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct CloudModelConfigurationView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  var preset: CloudModelPreset
  var onModelAdded: ((SignalASIContact) -> Void)? = nil
  @State private var displayName: String
  @State private var modelId: String
  @State private var endpoint: String
  @State private var apiKey = ""
  @State private var errorText = ""
  @State private var createdContactId: String?
  @State private var chatPresented = false

  init(
    preset: CloudModelPreset,
    onModelAdded: ((SignalASIContact) -> Void)? = nil
  ) {
    self.preset = preset
    self.onModelAdded = onModelAdded
    _displayName = State(initialValue: preset.name)
    _modelId = State(initialValue: preset.modelId)
    _endpoint = State(initialValue: preset.endpoint)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.cloud.config_title", "Configure Model"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CloudModelHeroView(
            title: preset.name,
            subtitle: "\(preset.provider) - \(preset.apiStyle.rawValue)",
            systemImage: "cloud.fill",
            assetImageName: providerLogoAssetName(preset.provider),
            tint: providerTint(preset.provider),
            badge: "API"
          )
          sectionTitle(t("signalasi.cloud.section_contact", "Contact"))
          CloudModelTextFieldRow(
            title: t("signalasi.cloud.contact_name", "Contact Name"),
            text: $displayName
          )
          sectionTitle("Provider")
          CloudModelValueRow(
            title: "Provider",
            value: preset.provider,
            systemImage: "cloud.fill",
            assetImageName: providerLogoAssetName(preset.provider),
            tint: providerTint(preset.provider)
          )
          sectionTitle(t("signalasi.cloud.section_model", "Model"))
          CloudModelTextFieldRow(
            title: t("signalasi.cloud.model_id", "Model ID"),
            text: $modelId,
            autocapitalization: .never
          )
          CloudModelTextFieldRow(
            title: "API Endpoint",
            text: $endpoint,
            keyboardType: .URL,
            autocapitalization: .never
          )
          sectionTitle(t("signalasi.cloud.section_key", "Key"))
          CloudModelSecureFieldRow(
            title: "API Key",
            text: $apiKey
          )
          if !errorText.isEmpty {
            Text(errorText)
              .font(.system(size: 13))
              .foregroundColor(.red)
              .padding(.horizontal, 4)
          }
          Button {
            saveAndStartChat()
          } label: {
            Text(t("signalasi.cloud.save_start_chat", "Save and Start Chat"))
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity, minHeight: 46)
              .background(canSave ? Color.signalASIAccent : Color.signalASITextSecondary)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          .disabled(!canSave)
          NavigationLink(destination: chatDestination, isActive: $chatPresented) {
            EmptyView()
          }
          .hidden()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var canSave: Bool {
    !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      CloudModelCredentialPolicy.isStoredCredential(apiKey)
  }

  @ViewBuilder
  private var chatDestination: some View {
    if let createdContactId {
      ConversationView(contactId: createdContactId)
    } else {
      EmptyView()
    }
  }

  private func saveAndStartChat() {
    do {
      let contact = try store.addCloudModelContact(
        displayName: displayName,
        provider: preset.provider,
        modelId: modelId,
        endpoint: endpoint,
        apiKey: apiKey,
        apiStyle: preset.apiStyle
      )
      createdContactId = contact.id
      errorText = ""
      if let onModelAdded {
        onModelAdded(contact)
      } else {
        chatPresented = true
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private enum CloudModelOnboardingCopy {
  static func providerSubtitle(_ provider: String, language: String) -> String {
    switch provider {
    case "OpenAI":
      return t("signalasi.cloud.provider.openai.subtitle", "GPT-5.5, GPT-5.4 mini/nano, and other OpenAI API models", language: language)
    case "Anthropic":
      return t("signalasi.cloud.provider.anthropic.subtitle", "Claude Opus, Sonnet, Haiku; uses Messages API", language: language)
    case "Google Gemini":
      return t("signalasi.cloud.provider.gemini.subtitle", "Gemini Pro / Flash / Flash Lite; direct Google API from the phone", language: language)
    case "DeepSeek":
      return t("signalasi.cloud.provider.deepseek.subtitle", "DeepSeek V4 Pro, V4 Flash", language: language)
    case "Qwen":
      return t("signalasi.cloud.provider.qwen.subtitle", "Qwen 3.7 Max/Plus, Qwen 3.6 Flash; DashScope OpenAI compatible", language: language)
    case "OpenRouter":
      return t("signalasi.cloud.provider.openrouter.subtitle", "Unified access to multiple cloud models with custom routing", language: language)
    default:
      return t("signalasi.cloud.provider.custom.subtitle", "OpenAI-compatible custom endpoint", language: language)
    }
  }

  private static func t(_ key: String, _ fallback: String, language: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: language)
  }
}

private struct CloudModelHeroView: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String? = nil
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      CloudModelProviderIconView(
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint,
        size: 52,
        symbolSize: 24
      )
      VStack(alignment: .leading, spacing: 4) {
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

private struct CloudModelNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String?
  var tint: Color
  var badge: String
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    assetImageName: String? = nil,
    tint: Color,
    badge: String,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.assetImageName = assetImageName
    self.tint = tint
    self.badge = badge
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      CloudModelRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint,
        badge: badge
      )
    }
    .buttonStyle(.plain)
  }
}

private struct CloudModelValueRow: View {
  var title: String
  var value: String
  var systemImage: String
  var assetImageName: String? = nil
  var tint: Color

  var body: some View {
    HStack(spacing: 12) {
      CloudModelProviderIconView(
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint,
        size: 42,
        symbolSize: 18
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
        Text(value)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CloudModelTextFieldRow: View {
  var title: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default
  var autocapitalization: TextInputAutocapitalization? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
      TextField(title, text: $text)
        .font(.system(size: 16))
        .foregroundColor(.signalASITextPrimary)
        .keyboardType(keyboardType)
        .textInputAutocapitalization(autocapitalization)
        .autocorrectionDisabled(true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CloudModelSecureFieldRow: View {
  var title: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
      SecureField(title, text: $text)
        .font(.system(size: 16))
        .foregroundColor(.signalASITextPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CloudModelRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String? = nil
  var tint: Color
  var badge: String

  var body: some View {
    HStack(spacing: 12) {
      CloudModelProviderIconView(
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint,
        size: 42,
        symbolSize: 18
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CloudModelProviderIconView: View {
  var systemImage: String
  var assetImageName: String?
  var tint: Color
  var size: CGFloat
  var symbolSize: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(tint.opacity(0.16))
      if let assetImageName {
        Image(assetImageName)
          .resizable()
          .scaledToFit()
          .padding(size * 0.18)
          .accessibilityHidden(true)
      } else {
        Image(systemName: systemImage)
          .font(.system(size: symbolSize, weight: .semibold))
          .foregroundColor(tint)
      }
    }
    .frame(width: size, height: size)
  }
}

private func providerLogoAssetName(_ provider: String) -> String? {
  switch provider {
  case "OpenAI":
    return "CloudProviderOpenAI"
  case "Anthropic":
    return "CloudProviderAnthropic"
  case "Google Gemini":
    return "CloudProviderGemini"
  case "DeepSeek":
    return "CloudProviderDeepSeek"
  case "Qwen":
    return "CloudProviderQwen"
  case "OpenRouter":
    return "CloudProviderOpenRouter"
  default:
    return nil
  }
}

private func providerTint(_ provider: String) -> Color {
  switch provider {
  case "OpenAI":
    return .signalASIAccent
  case "Anthropic":
    return .red
  case "Google Gemini":
    return .blue
  case "DeepSeek":
    return .blue
  case "Qwen":
    return .teal
  case "OpenRouter":
    return .purple
  default:
    return .signalASITextSecondary
  }
}
