import SwiftUI

struct GalaxySSICloudModelSwitchView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  var contactId: String
  var dismissAfterSelection: Bool = false
  @State private var statusMessage = ""

  private var contact: GalaxySSIContact? {
    store.contact(id: contactId)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.cloud.switch_model_title", "Switch Model"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          if let contact {
            NavigationLink(destination: CloudModelPickerView(provider: provider(for: contact))) {
              Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.galaxySSITextPrimary)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
          } else {
            Color.clear
          }
        }
      )
      if let contact {
        content(for: contact)
      } else {
        missingContactContent
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func content(for contact: GalaxySSIContact) -> some View {
    let provider = provider(for: contact)
    return ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        GalaxySSISecurityHeroView(
          title: provider,
          subtitle: heroSubtitle(for: contact),
          systemImage: "cloud.fill",
          tint: cloudSwitchProviderTint(provider),
          badge: t("galaxyssi.cloud.select_model", "Select Model")
        )
        if !statusMessage.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.cloud.switch.status", "Status"),
            subtitle: statusMessage,
            systemImage: "info.circle.fill",
            tint: .galaxySSIInsightText,
            badge: ""
          )
        }
        if let selected = contact.selectedCloudModel {
          GalaxySSISecuritySectionTitle(title: t("galaxyssi.cloud.switch.current_section", "Current"))
          GalaxySSISecurityStatusRow(
            title: selected.displayName.ifBlank(selected.modelId),
            subtitle: selectedSubtitle(selected),
            systemImage: "checkmark.seal.fill",
            tint: .galaxySSIAccent,
            badge: readinessBadge(for: selected, contact: contact),
            monospacedSubtitle: true
          )
        }
        GalaxySSISecuritySectionTitle(title: t("galaxyssi.cloud.section_model", "Model"))
        modelList(for: contact)
        GalaxySSISecuritySectionTitle(title: t("galaxyssi.cloud.switch.actions_section", "Actions"))
        GalaxySSISecurityNavigationRow(
          title: t("galaxyssi.cloud.switch.add_model", "Add Model"),
          subtitle: String(
            format: t("galaxyssi.cloud.switch.add_model_subtitle", "Configure another %@ model or custom model ID."),
            provider
          ),
          systemImage: "plus.circle.fill",
          tint: cloudSwitchProviderTint(provider),
          badge: t("galaxyssi.common.add", "Add")
        ) {
          CloudModelPickerView(provider: provider)
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 18)
    }
  }

  @ViewBuilder
  private func modelList(for contact: GalaxySSIContact) -> some View {
    let rows = switchOptions(for: contact)
    if rows.isEmpty {
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.cloud.no_models", "No models"),
        subtitle: t("galaxyssi.cloud.no_models_subtitle", "Add a model configuration before switching."),
        systemImage: "plus.circle",
        tint: cloudSwitchProviderTint(provider(for: contact)),
        badge: t("galaxyssi.common.add", "Add")
      ) {
        CloudModelPickerView(provider: provider(for: contact))
      }
    } else {
      VStack(spacing: 8) {
        ForEach(rows) { option in
          let selected = isSelected(option, contact: contact)
          GalaxySSISecurityActionRow(
            title: option.displayName,
            subtitle: optionSubtitle(option),
            systemImage: selected ? "checkmark.circle.fill" : option.systemImage,
            tint: selected ? .galaxySSIAccent : cloudSwitchProviderTint(option.provider),
            badge: selected ? t("galaxyssi.cloud.current", "Current") : t("galaxyssi.common.select", "Select"),
            monospacedSubtitle: true
          ) {
            select(option, contact: contact)
          }
        }
      }
    }
  }

  private var missingContactContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        GalaxySSISecurityHeroView(
          title: t("galaxyssi.cloud.models_title", "Cloud Models"),
          subtitle: t("galaxyssi.cloud.switch.missing_contact", "Cloud model contact was not found."),
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange,
          badge: t("galaxyssi.status.unknown", "Unknown")
        )
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 18)
    }
  }

  private func switchOptions(for contact: GalaxySSIContact) -> [CloudModelSwitchOption] {
    let provider = provider(for: contact)
    var rows: [CloudModelSwitchOption] = []
    var indexesByModelId: [String: Int] = [:]

    func upsert(_ option: CloudModelSwitchOption) {
      if let index = indexesByModelId[option.modelId] {
        rows[index] = option
      } else {
        indexesByModelId[option.modelId] = rows.count
        rows.append(option)
      }
    }

    CloudModelPreset.androidParity
      .filter { $0.provider.localizedCaseInsensitiveCompare(provider) == .orderedSame }
      .forEach { preset in
        upsert(
          CloudModelSwitchOption(
            displayName: preset.name,
            provider: preset.provider,
            modelId: preset.modelId,
            endpoint: preset.endpoint,
            apiStyle: preset.apiStyle,
            storedModel: nil
          )
        )
      }

    contact.cloudModels.forEach { model in
      upsert(
        CloudModelSwitchOption(
          displayName: model.displayName.ifBlank(model.modelId),
          provider: model.provider.ifBlank(provider),
          modelId: model.modelId,
          endpoint: model.endpoint,
          apiStyle: model.apiStyle,
          storedModel: model
        )
      )
    }

    return rows
  }

  private func select(_ option: CloudModelSwitchOption, contact: GalaxySSIContact) {
    if store.setSelectedCloudModel(contactId: contact.id, modelId: option.modelId) {
      showSelectionSuccess(option)
      return
    }
    guard let apiKey = reusableAPIKey(from: contact) else {
      statusMessage = String(
        format: t("galaxyssi.cloud.configure_api_key_first", "Configure the API Key for %@ first."),
        option.provider
      )
      return
    }
    do {
      let updated = try store.addCloudModelContact(
        displayName: option.displayName,
        provider: option.provider,
        modelId: option.modelId,
        endpoint: option.endpoint,
        apiKey: apiKey,
        apiStyle: option.apiStyle
      )
      if store.setSelectedCloudModel(contactId: updated.id, modelId: option.modelId) {
        showSelectionSuccess(option)
      } else {
        statusMessage = t("galaxyssi.cloud.switch.failed", "Model switch failed. Please configure the model first.")
      }
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func showSelectionSuccess(_ option: CloudModelSwitchOption) {
    statusMessage = String(
      format: t("galaxyssi.cloud.switched_model", "Switched to %@."),
      option.displayName
    )
    if dismissAfterSelection {
      dismiss()
    }
  }

  private func reusableAPIKey(from contact: GalaxySSIContact) -> String? {
    contact.cloudModels
      .compactMap { store.apiKey(for: $0) }
      .first { CloudModelCredentialPolicy.isStoredCredential($0) }
  }

  private func provider(for contact: GalaxySSIContact) -> String {
    contact.cloudProvider.ifBlank(contact.displayName).ifBlank("Custom")
  }

  private func heroSubtitle(for contact: GalaxySSIContact) -> String {
    let selected = contact.selectedCloudModel?.modelId ?? t("galaxyssi.settings.no_model", "No model")
    let count = String(
      format: t("galaxyssi.cloud.switch.model_count", "%d configured"),
      contact.cloudModels.count
    )
    return "\(selected) - \(count)"
  }

  private func selectedSubtitle(_ model: CloudModelConfig) -> String {
    "\(model.modelId)\n\(model.apiStyle.rawValue) - \(model.endpoint)"
  }

  private func optionSubtitle(_ option: CloudModelSwitchOption) -> String {
    let setup = option.storedModel == nil
      ? t("galaxyssi.cloud.switch.needs_key", "Needs API key")
      : t("galaxyssi.cloud.switch.configured", "Configured")
    return "\(option.modelId)\n\(setup) - \(option.endpoint)"
  }

  private func readinessBadge(for model: CloudModelConfig, contact: GalaxySSIContact) -> String {
    let ready = CloudModelCredentialPolicy.isAutoRoutable(
      model: model,
      apiKey: store.apiKey(for: model),
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    )
    return ready ? t("galaxyssi.cloud.switch.ready", "Ready") : t("galaxyssi.cloud.switch.needs_setup", "Needs Setup")
  }

  private func isSelected(_ option: CloudModelSwitchOption, contact: GalaxySSIContact) -> Bool {
    contact.selectedCloudModel?.modelId == option.modelId
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct CloudModelSwitchOption: Identifiable {
  var id: String { "\(provider):\(modelId)" }
  var displayName: String
  var provider: String
  var modelId: String
  var endpoint: String
  var apiStyle: GalaxySSICloudAPIStyle
  var storedModel: CloudModelConfig?

  var systemImage: String {
    storedModel == nil ? "link" : "cloud.fill"
  }
}

private func cloudSwitchProviderTint(_ provider: String) -> Color {
  switch provider {
  case "OpenAI":
    return cloudSwitchColor(0x14C66A)
  case "Anthropic":
    return cloudSwitchColor(0xFF6B5F)
  case "Google Gemini":
    return cloudSwitchColor(0x5B6CFF)
  case "DeepSeek":
    return cloudSwitchColor(0x3F84FF)
  case "Qwen":
    return cloudSwitchColor(0x00A7A7)
  case "OpenRouter":
    return cloudSwitchColor(0x7C5CFF)
  default:
    return cloudSwitchColor(0x6C7A89)
  }
}

private func cloudSwitchColor(_ rgb: UInt32) -> Color {
  Color(
    red: Double((rgb >> 16) & 0xFF) / 255.0,
    green: Double((rgb >> 8) & 0xFF) / 255.0,
    blue: Double(rgb & 0xFF) / 255.0
  )
}
