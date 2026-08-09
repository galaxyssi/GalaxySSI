import SwiftUI

enum AgentModelSelectionMode: String, Codable {
  case automatic
  case manual
}

struct AgentModelSelection: Codable, Equatable {
  var mode: AgentModelSelectionMode = .automatic
  var targetId = ""
  var modelId = ""
  var displayName = ""
}

enum AgentModelSelectionSettings {
  private static let storageKey = "signalasi_agent_model_selection_v1"

  static func hasStoredSelection(defaults: UserDefaults = .standard) -> Bool {
    defaults.data(forKey: storageKey) != nil
  }

  static func selection(defaults: UserDefaults = .standard) -> AgentModelSelection {
    guard let data = defaults.data(forKey: storageKey),
          let value = try? JSONDecoder().decode(AgentModelSelection.self, from: data) else {
      return AgentModelSelection()
    }
    return value
  }

  static func selectAutomatic(defaults: UserDefaults = .standard) {
    save(AgentModelSelection(), defaults: defaults)
  }

  static func selectManual(
    targetId: String,
    modelId: String,
    displayName: String,
    defaults: UserDefaults = .standard
  ) {
    let cleanTargetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTargetId.isEmpty else { return }
    save(
      AgentModelSelection(
        mode: .manual,
        targetId: cleanTargetId,
        modelId: String(modelId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
        displayName: String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
      ),
      defaults: defaults
    )
  }

  private static func save(_ value: AgentModelSelection, defaults: UserDefaults) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: storageKey)
  }
}

struct SignalASIAgentModelSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var onSelectionChanged: (() -> Void)?

  private var selection: AgentModelSelection {
    AgentModelSelectionSettings.selection()
  }

  private var localProfiles: [LocalModelRuntimeProfile] {
    LocalModelRuntimeCatalog.profiles().filter {
      LocalModelRuntimeSettings.isProfileEnabled($0) &&
        LocalModelInferenceRuntime.shared.ready(profile: $0)
    }
  }

  private var cloudContacts: [SignalASIContact] {
    store.cloudModelContacts.filter { contact in
      AgentConnectorAvailability.cloudModelReady(
        contact: contact,
        apiKey: contact.selectedCloudModel.flatMap(store.apiKey(for:))
      )
    }
  }

  private var callableTargets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  private var agentTargets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.selectableAgentTargets(callableTargets)
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  private var preferredTargetId: String {
    AgentCallableTargetCatalog.preferredTargetId(
      selection: selection,
      targets: callableTargets
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.agent.model_selection.title", "Select model or Agent"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("signalasi.agent.model_selection.hero_title", "Agent model"),
            subtitle: selectionSubtitle,
            systemImage: "cpu.fill",
            tint: .signalASIAccent,
            badge: t("signalasi.agent.model_selection.badge", "Routing")
          )
          SignalASISecuritySectionTitle(
            title: t("signalasi.agent.model_selection.routing_section", "ROUTING")
          )
          SignalASISecurityActionRow(
            title: t("signalasi.agent.model_selection.automatic", "Automatic"),
            subtitle: t(
              "signalasi.agent.model_selection.automatic_subtitle",
              "Choose by task, speed, privacy, and availability"
            ),
            systemImage: isAutomatic ? "checkmark.circle.fill" : "arrow.triangle.branch",
            tint: isAutomatic ? .signalASIAccent : .signalASIInsightText,
            badge: isAutomatic
              ? t("signalasi.agent.model_selection.current", "Current")
              : t("signalasi.common.select", "Select")
          ) {
            selectAutomatic()
          }

          if !localProfiles.isEmpty {
            SignalASISecuritySectionTitle(
              title: t("signalasi.agent.model_selection.local_section", "ON-DEVICE MODELS")
            )
            ForEach(localProfiles) { profile in
              let selected = isSelectedLocal(profile)
              SignalASISecurityActionRow(
                title: profile.displayName,
                subtitle: t(
                  "signalasi.agent.model_selection.local_subtitle",
                  "Installed and ready on this iPhone"
                ),
                systemImage: selected ? "checkmark.circle.fill" : "iphone",
                tint: selected ? .signalASIAccent : .blue,
                badge: selected
                  ? t("signalasi.agent.model_selection.current", "Current")
                  : t("signalasi.common.select", "Select"),
                monospacedSubtitle: true
              ) {
                selectLocal(profile)
              }
            }
          }

          if !agentTargets.isEmpty {
            SignalASISecuritySectionTitle(
              title: t("signalasi.agent.model_selection.agent_section", "AGENTS")
            )
            ForEach(agentTargets) { target in
              let selected = isSelectedAgent(target)
              SignalASISecurityActionRow(
                title: target.title,
                subtitle: t(
                  "signalasi.agent.model_selection.agent_subtitle",
                  "Connected and ready Agent"
                ),
                systemImage: selected ? "checkmark.circle.fill" : "person.2.fill",
                tint: selected ? .signalASIAccent : .indigo,
                badge: selected
                  ? t("signalasi.agent.model_selection.current", "Current")
                  : t("signalasi.common.select", "Select")
              ) {
                selectAgent(target)
              }
            }
          }

          if !cloudContacts.isEmpty {
            SignalASISecuritySectionTitle(
              title: t("signalasi.agent.model_selection.cloud_section", "CLOUD MODELS")
            )
            ForEach(cloudContacts) { contact in
              if let model = contact.selectedCloudModel {
                let selected = isSelectedCloud(contact)
                SignalASISecurityActionRow(
                  title: model.displayName.ifBlank(model.modelId),
                  subtitle: "\(contact.displayName) - \(model.modelId)",
                  systemImage: selected ? "checkmark.circle.fill" : "cloud.fill",
                  tint: selected ? .signalASIAccent : cloudModelTint(contact.cloudProvider),
                  badge: selected
                    ? t("signalasi.agent.model_selection.current", "Current")
                    : t("signalasi.common.select", "Select"),
                  monospacedSubtitle: true
                ) {
                  selectCloud(contact, model: model)
                }
              }
            }
          }

          if localProfiles.isEmpty && agentTargets.isEmpty && cloudContacts.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.agent.model_selection.no_models", "No ready models"),
              subtitle: t(
                "signalasi.agent.model_selection.no_models_subtitle",
                "Configure a cloud model, install a local model, or connect an Agent in Settings."
              ),
              systemImage: "exclamationmark.triangle.fill",
              tint: .orange,
              badge: t("signalasi.status.needs_setup", "Needs Setup")
            )
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

  private var isAutomatic: Bool {
    selection.mode == .automatic ||
      selection.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var selectedManualTarget: (title: String, subtitle: String)? {
    guard selection.mode == .manual else { return nil }
    let targetId = selection.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !targetId.isEmpty else { return nil }

    if targetId == "local-llm" {
      let profile = LocalModelRuntimeCatalog.find(selection.modelId)
      let ready = LocalModelRuntimeSettings.isProfileEnabled(profile) &&
        LocalModelInferenceRuntime.shared.ready(profile: profile)
      let title = profile.displayName
        .ifBlank(selection.displayName)
        .ifBlank(selection.modelId)
        .ifBlank(targetId)
      return (
        title,
        ready
          ? t("signalasi.agent.model_selection.on_device", "On device")
          : t("signalasi.agent.model_selection.unavailable", "Unavailable")
      )
    }

    if let contact = store.contact(id: targetId) {
      if contact.type == "agent" {
        let title = contact.displayName
          .ifBlank(contact.name)
          .ifBlank(selection.displayName)
          .ifBlank(contact.id)
        let ready = preferredTargetId == targetId
        return (
          title,
          ready
            ? t("signalasi.agent.model_selection.on_agent", "Agent")
            : t("signalasi.agent.model_selection.unavailable", "Unavailable")
        )
      }

      if let model = contact.selectedCloudModel {
        let ready = AgentConnectorAvailability.cloudModelReady(
          contact: contact,
          apiKey: contact.selectedCloudModel.flatMap(store.apiKey(for:))
        )
        return (
          model.displayName
            .ifBlank(model.modelId)
            .ifBlank(selection.displayName)
            .ifBlank(targetId),
          ready
            ? contact.displayName
            : t("signalasi.agent.model_selection.unavailable", "Unavailable")
        )
      }
    }

    return (
      selection.displayName.ifBlank(targetId),
      t("signalasi.agent.model_selection.unavailable", "Unavailable")
    )
  }

  private var selectionSubtitle: String {
    selectedManualTarget.map { "\($0.title) - \($0.subtitle)" }
      ?? t("signalasi.agent.model_selection.automatic", "Automatic")
  }

  private func isSelectedLocal(_ profile: LocalModelRuntimeProfile) -> Bool {
    selection.mode == .manual &&
      selection.targetId == "local-llm" &&
      selection.modelId == profile.id
  }

  private func isSelectedCloud(_ contact: SignalASIContact) -> Bool {
    selection.mode == .manual && selection.targetId == contact.id
  }

  private func isSelectedAgent(_ target: AgentCallableTarget) -> Bool {
    preferredTargetId == target.id
  }

  private func selectAutomatic() {
    AgentModelSelectionSettings.selectAutomatic()
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: t("signalasi.agent.model_selection.automatic", "Automatic")
    )
    finishSelection()
  }

  private func selectLocal(_ profile: LocalModelRuntimeProfile) {
    LocalModelRuntimeSettings.setSelectedProfile(profile.id)
    AgentModelSelectionSettings.selectManual(
      targetId: "local-llm",
      modelId: profile.id,
      displayName: profile.displayName
    )
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: profile.displayName
    )
    finishSelection()
  }

  private func selectCloud(_ contact: SignalASIContact, model: CloudModelConfig) {
    AgentModelSelectionSettings.selectManual(
      targetId: contact.id,
      modelId: model.modelId,
      displayName: model.displayName.ifBlank(model.modelId)
    )
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: model.displayName.ifBlank(model.modelId)
    )
    finishSelection()
  }

  private func selectAgent(_ target: AgentCallableTarget) {
    let title = target.title
    AgentModelSelectionSettings.selectManual(
      targetId: target.id,
      modelId: "",
      displayName: title
    )
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: title
    )
    finishSelection()
  }

  private func finishSelection() {
    onSelectionChanged?()
    dismiss()
  }

  private func cloudModelTint(_ provider: String) -> Color {
    switch provider.lowercased() {
    case "openai": return .green
    case "anthropic", "claude": return .orange
    case "gemini", "google gemini": return .blue
    case "deepseek": return .indigo
    case "qwen": return .teal
    default: return .signalASIInsightText
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
