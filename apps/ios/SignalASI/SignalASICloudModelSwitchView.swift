import SwiftUI

struct SignalASICloudModelSwitchView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  var contactId: String
  var dismissAfterSelection: Bool = false
  @State private var statusMessage = ""

  private var contact: SignalASIContact? {
    store.contact(id: contactId)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.cloud.switch_model_title", "Switch Model"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          if let contact {
            NavigationLink(destination: CloudModelPickerView(provider: provider(for: contact))) {
              Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func content(for contact: SignalASIContact) -> some View {
    let provider = provider(for: contact)
    return ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SignalASISecurityHeroView(
          title: provider,
          subtitle: heroSubtitle(for: contact),
          systemImage: "cloud.fill",
          tint: cloudSwitchProviderTint(provider),
          badge: t("signalasi.cloud.select_model", "Select Model")
        )
        if !statusMessage.isEmpty {
          SignalASISecurityStatusRow(
            title: t("signalasi.cloud.switch.status", "Status"),
            subtitle: statusMessage,
            systemImage: "info.circle.fill",
            tint: .signalASIInsightText,
            badge: ""
          )
        }
        if let selected = contact.selectedCloudModel {
          SignalASISecuritySectionTitle(title: t("signalasi.cloud.switch.current_section", "Current"))
          SignalASISecurityStatusRow(
            title: selected.displayName.ifBlank(selected.modelId),
            subtitle: selectedSubtitle(selected),
            systemImage: "checkmark.seal.fill",
            tint: .signalASIAccent,
            badge: readinessBadge(for: selected, contact: contact),
            monospacedSubtitle: true
          )
        }
        SignalASISecuritySectionTitle(title: t("signalasi.cloud.section_model", "Model"))
        modelList(for: contact)
        SignalASISecuritySectionTitle(title: t("signalasi.cloud.switch.actions_section", "Actions"))
        SignalASISecurityNavigationRow(
          title: t("signalasi.cloud.switch.add_model", "Add Model"),
          subtitle: String(
            format: t("signalasi.cloud.switch.add_model_subtitle", "Configure another %@ model or custom model ID."),
            provider
          ),
          systemImage: "plus.circle.fill",
          tint: cloudSwitchProviderTint(provider),
          badge: t("signalasi.common.add", "Add")
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
  private func modelList(for contact: SignalASIContact) -> some View {
    let rows = switchOptions(for: contact)
    if rows.isEmpty {
      SignalASISecurityNavigationRow(
        title: t("signalasi.cloud.no_models", "No models"),
        subtitle: t("signalasi.cloud.no_models_subtitle", "Add a model configuration before switching."),
        systemImage: "plus.circle",
        tint: cloudSwitchProviderTint(provider(for: contact)),
        badge: t("signalasi.common.add", "Add")
      ) {
        CloudModelPickerView(provider: provider(for: contact))
      }
    } else {
      VStack(spacing: 8) {
        ForEach(rows) { option in
          let selected = isSelected(option, contact: contact)
          SignalASISecurityActionRow(
            title: option.displayName,
            subtitle: optionSubtitle(option),
            systemImage: selected ? "checkmark.circle.fill" : option.systemImage,
            tint: selected ? .signalASIAccent : cloudSwitchProviderTint(option.provider),
            badge: selected ? t("signalasi.cloud.current", "Current") : t("signalasi.common.select", "Select"),
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
        SignalASISecurityHeroView(
          title: t("signalasi.cloud.models_title", "Cloud Models"),
          subtitle: t("signalasi.cloud.switch.missing_contact", "Cloud model contact was not found."),
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange,
          badge: t("signalasi.status.unknown", "Unknown")
        )
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 18)
    }
  }

  private func switchOptions(for contact: SignalASIContact) -> [CloudModelSwitchOption] {
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

  private func select(_ option: CloudModelSwitchOption, contact: SignalASIContact) {
    if store.setSelectedCloudModel(contactId: contact.id, modelId: option.modelId) {
      showSelectionSuccess(option)
      return
    }
    guard let apiKey = reusableAPIKey(from: contact) else {
      statusMessage = String(
        format: t("signalasi.cloud.configure_api_key_first", "Configure the API Key for %@ first."),
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
        statusMessage = t("signalasi.cloud.switch.failed", "Model switch failed. Please configure the model first.")
      }
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func showSelectionSuccess(_ option: CloudModelSwitchOption) {
    statusMessage = String(
      format: t("signalasi.cloud.switched_model", "Switched to %@."),
      option.displayName
    )
    if dismissAfterSelection {
      dismiss()
    }
  }

  private func reusableAPIKey(from contact: SignalASIContact) -> String? {
    contact.cloudModels
      .compactMap { store.apiKey(for: $0) }
      .first { CloudModelCredentialPolicy.isStoredCredential($0) }
  }

  private func provider(for contact: SignalASIContact) -> String {
    contact.cloudProvider.ifBlank(contact.displayName).ifBlank("Custom")
  }

  private func heroSubtitle(for contact: SignalASIContact) -> String {
    let selected = contact.selectedCloudModel?.modelId ?? t("signalasi.settings.no_model", "No model")
    let count = String(
      format: t("signalasi.cloud.switch.model_count", "%d configured"),
      contact.cloudModels.count
    )
    return "\(selected) - \(count)"
  }

  private func selectedSubtitle(_ model: CloudModelConfig) -> String {
    "\(model.modelId)\n\(model.apiStyle.rawValue) - \(model.endpoint)"
  }

  private func optionSubtitle(_ option: CloudModelSwitchOption) -> String {
    let setup = option.storedModel == nil
      ? t("signalasi.cloud.switch.needs_key", "Needs API key")
      : t("signalasi.cloud.switch.configured", "Configured")
    return "\(option.modelId)\n\(setup) - \(option.endpoint)"
  }

  private func readinessBadge(for model: CloudModelConfig, contact: SignalASIContact) -> String {
    let ready = CloudModelCredentialPolicy.isAutoRoutable(
      model: model,
      apiKey: store.apiKey(for: model),
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    )
    return ready ? t("signalasi.cloud.switch.ready", "Ready") : t("signalasi.cloud.switch.needs_setup", "Needs Setup")
  }

  private func isSelected(_ option: CloudModelSwitchOption, contact: SignalASIContact) -> Bool {
    contact.selectedCloudModel?.modelId == option.modelId
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct CloudModelSwitchOption: Identifiable {
  var id: String { "\(provider):\(modelId)" }
  var displayName: String
  var provider: String
  var modelId: String
  var endpoint: String
  var apiStyle: SignalASICloudAPIStyle
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
