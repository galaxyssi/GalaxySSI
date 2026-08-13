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
  private static let conversationKeyPrefix = "conversation."
  private static let maxConversationIdLength = 160

  static func hasStoredSelection(
    for conversationId: String,
    defaults: UserDefaults = .standard
  ) -> Bool {
    guard let key = storageKey(for: conversationId, field: "selection") else { return false }
    return defaults.data(forKey: key) != nil
  }

  static func selection(
    for conversationId: String,
    defaults: UserDefaults = .standard
  ) -> AgentModelSelection {
    guard let key = storageKey(for: conversationId, field: "selection"),
          let data = defaults.data(forKey: key),
          let value = try? JSONDecoder().decode(AgentModelSelection.self, from: data) else {
      return AgentModelSelection()
    }
    return value
  }

  static func selectAutomatic(
    for conversationId: String,
    defaults: UserDefaults = .standard
  ) {
    save(AgentModelSelection(), for: conversationId, defaults: defaults)
  }

  static func selectManual(
    for conversationId: String,
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
      for: conversationId,
      defaults: defaults
    )
  }

  static func clearConversation(
    _ conversationId: String,
    defaults: UserDefaults = .standard
  ) {
    guard let key = storageKey(for: conversationId, field: "selection") else { return }
    defaults.removeObject(forKey: key)
  }

  private static func save(
    _ value: AgentModelSelection,
    for conversationId: String,
    defaults: UserDefaults
  ) {
    guard let key = storageKey(for: conversationId, field: "selection"),
          let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: key)
  }

  private static func storageKey(for conversationId: String, field: String) -> String? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    let scope = String(clean.prefix(maxConversationIdLength))
    return "\(conversationKeyPrefix)\(scope).\(field)"
  }
}

struct SignalASIAgentModelSelectionPreparedContent {
  var localProfiles: [LocalModelRuntimeProfile]
  var cloudContacts: [SignalASIContact]
  var callableTargets: [AgentCallableTarget]
}

struct SignalASIAgentModelSelectionView: View {
  private struct ReadyCloudModel: Identifiable {
    var contact: SignalASIContact
    var model: CloudModelConfig

    var id: String { "\(contact.id):\(model.modelId)" }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator

  var onSelectionChanged: (() -> Void)?
  @State private var contentLoading = true
  @State private var modelSelectionRefreshToken = UUID()
  @State private var navigationContentGate = SignalASINavigationContentGate()
  @State private var preparedContent = SignalASIAgentModelSelectionPreparedContent(
    localProfiles: [],
    cloudContacts: [],
    callableTargets: []
  )

  private var selection: AgentModelSelection {
    AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
  }

  private var localProfiles: [LocalModelRuntimeProfile] {
    preparedContent.localProfiles
  }

  private var cloudContacts: [SignalASIContact] {
    preparedContent.cloudContacts
  }

  private var readyCloudModels: [ReadyCloudModel] {
    cloudContacts.flatMap { contact in
      contact.cloudModels.compactMap { model in
        guard AgentConnectorAvailability.cloudModelReady(
          model: model,
          apiKey: store.apiKey(for: model),
          provider: contact.cloudProvider,
          setupStatus: contact.setupStatus
        ) else {
          return nil
        }
        return ReadyCloudModel(contact: contact, model: model)
      }
    }
  }

  private var callableTargets: [AgentCallableTarget] {
    preparedContent.callableTargets
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

  private var selectedManualTargetIsVisible: Bool {
    guard selection.mode == .manual else { return true }
    let targetId = selection.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !targetId.isEmpty else { return true }
    if targetId == "local-llm" {
      return localProfiles.contains { $0.id == selection.modelId }
    }
    if agentTargets.contains(where: { $0.id == targetId }) {
      return true
    }
    guard let contact = cloudContacts.first(where: { $0.id == targetId }) else {
      return false
    }
    return selectedCloudModel(in: contact, modelId: selection.modelId).map { model in
      AgentConnectorAvailability.cloudModelReady(
        model: model,
        apiKey: store.apiKey(for: model),
        provider: contact.cloudProvider,
        setupStatus: contact.setupStatus
      )
    } ?? false
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.agent.model_selection.title", "Select model or Agent"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        if contentLoading {
          modelSelectionLoadingContent
        } else {
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

          if selection.mode == .manual,
             let selectedManualTarget,
             !selectedManualTargetIsVisible {
            SignalASISecurityStatusRow(
              title: selectedManualTarget.title,
              subtitle: t(
                "signalasi.agent.model_selection.unavailable_subtitle",
                "The selected target is currently unavailable. Choose Automatic or another ready target."
              ),
              systemImage: "exclamationmark.triangle.fill",
              tint: .orange,
              badge: t("signalasi.agent.model_selection.unavailable", "Unavailable")
            )
          }

          if !localProfiles.isEmpty {
            SignalASISecuritySectionTitle(
              title: t("signalasi.agent.model_selection.local_section", "ON-DEVICE MODELS")
            )
            SignalASISecurityNavigationRow(
              title: t("signalasi.settings.local_model", "Local Model Settings"),
              subtitle: t(
                "signalasi.settings.local_model.status",
                "Configure on-device inference"
              ),
              systemImage: "arrow.down.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.common.manage", "Manage")
            ) {
              SignalASILocalModelLabView()
            }
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
          } else {
            SignalASISecuritySectionTitle(
              title: t("signalasi.agent.model_selection.local_section", "ON-DEVICE MODELS")
            )
            SignalASISecurityNavigationRow(
              title: t("signalasi.settings.local_model", "Local Model Settings"),
              subtitle: t(
                "signalasi.agent.model_selection.local_manage_subtitle",
                "Download and prepare an on-device model for private Agent work"
              ),
              systemImage: "arrow.down.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.common.manage", "Manage")
            ) {
              SignalASILocalModelLabView()
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
                assetImage: agentLogoAssetName(for: target),
                tint: selected ? .signalASIAccent : .indigo,
                badge: selected
                  ? t("signalasi.agent.model_selection.current", "Current")
                  : t("signalasi.common.select", "Select")
              ) {
                selectAgent(target)
              }
            }
          }

          SignalASISecuritySectionTitle(
            title: t("signalasi.agent.model_selection.connect_section", "CONNECT AN AGENT")
          )
          SignalASISecurityNavigationRow(
            title: t("signalasi.agent.model_selection.scan_agent", "Scan or paste Agent QR"),
            subtitle: t(
              "signalasi.agent.model_selection.scan_agent_subtitle",
              "Pair a trusted Desktop Agent or local model through the Android-compatible QR flow"
            ),
            systemImage: "qrcode.viewfinder",
            tint: .orange,
            badge: t("security_scan", "Scan")
          ) {
            AddContactView(autoOpenScanner: true)
          }

          if !readyCloudModels.isEmpty {
            SignalASISecuritySectionTitle(
              title: t("signalasi.agent.model_selection.cloud_section", "CLOUD MODELS")
            )
            ForEach(readyCloudModels) { item in
              let selected = isSelectedCloud(item.contact, model: item.model)
              SignalASISecurityActionRow(
                title: item.model.displayName.ifBlank(item.model.modelId),
                subtitle: "\(item.contact.displayName) - \(item.model.modelId)",
                systemImage: selected ? "checkmark.circle.fill" : "cloud.fill",
                assetImage: cloudLogoAssetName(for: item.contact.cloudProvider),
                tint: selected ? .signalASIAccent : cloudModelTint(item.contact.cloudProvider),
                badge: selected
                  ? t("signalasi.agent.model_selection.current", "Current")
                  : t("signalasi.common.select", "Select"),
                monospacedSubtitle: true
              ) {
                selectCloud(item.contact, model: item.model)
              }
            }
          }

          if localProfiles.isEmpty && agentTargets.isEmpty && readyCloudModels.isEmpty {
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
            SignalASISecurityNavigationRow(
              title: t("signalasi.discover.add_cloud_model", "Add Cloud Model"),
              subtitle: t(
                "signalasi.discover.add_cloud_model_subtitle",
                "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"
              ),
              systemImage: "cloud.fill",
              tint: .signalASIInsightText,
              badge: t("signalasi.common.add", "Add")
            ) {
              CloudModelProviderSelectionView()
            }
            SignalASISecurityNavigationRow(
              title: t("signalasi.agent_connection.scan_qr", "Scan or Paste Agent QR"),
              subtitle: t(
                "signalasi.agent_connection.scan_qr_subtitle",
                "Pair a trusted Desktop Agent or local model through the Android-compatible QR flow"
              ),
              systemImage: "qrcode.viewfinder",
              tint: .orange,
              badge: t("security_scan", "Scan")
            ) {
              AddContactView(autoOpenScanner: true)
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .signalASIContactImportDidComplete)) { _ in
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .signalASIDesktopPairingDidComplete)) { _ in
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .signalASIAgentRoutingDidUpdate)) { _ in
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onDisappear {
      navigationContentGate.invalidate()
    }
    .task(id: "\(modelSelectionContentTaskID)|\(modelSelectionRefreshToken.uuidString)") {
      await prepareModelSelectionContent()
    }
  }

  private var modelSelectionLoadingContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      SignalASISecurityHeroView(
        title: t("signalasi.agent.model_selection.hero_title", "Agent model"),
        subtitle: t("cc_loading", "Loading..."),
        systemImage: "cpu.fill",
        tint: .signalASIAccent,
        badge: t("signalasi.agent.model_selection.badge", "Routing")
      )
      HStack(spacing: 10) {
        ProgressView()
          .tint(.signalASIAccent)
        Text(t("cc_loading", "Loading..."))
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: 120)
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 18)
  }

  private var modelSelectionContentTaskID: String {
    let contacts = store.contacts.map {
      let models = $0.cloudModels.map { "\($0.modelId):\($0.displayName):\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: ",")
      return "\($0.id):\($0.updatedAt.timeIntervalSince1970):\($0.setupStatus):\($0.selectedCloudModelId):\(models)"
    }.joined(separator: "|")
    return "\(store.activeAgentConversationId)|\(contacts)"
  }

  private func prepareModelSelectionContent() async {
    let generation = navigationContentGate.begin()
    if let cached = SignalASINavigationContentPrewarm.snapshot(for: store)?.modelSelection,
       !Task.isCancelled {
      preparedContent = cached
      contentLoading = false
      return
    }
    contentLoading = true
    let sourceContacts = store.visibleContacts
    let sourceCloudContacts = store.cloudModelContacts
    let apiKeys = sourceCloudContacts.reduce(into: [String: String]()) { result, contact in
      for model in contact.cloudModels {
        if let key = store.apiKey(for: model), !key.isEmpty {
          result[model.keychainAccount] = key
        }
      }
    }
    let prepared = await Task.detached(priority: .userInitiated) {
      let localProfiles = LocalModelRuntimeSettings.activeProfiles()
      let callableTargets = AgentCallableTargetCatalog.build(
        contacts: sourceContacts,
        apiKey: { apiKeys[$0.keychainAccount] }
      )
      let cloudContacts = sourceCloudContacts.filter { contact in
        contact.cloudModels.contains { model in
          AgentConnectorAvailability.cloudModelReady(
            model: model,
            apiKey: apiKeys[model.keychainAccount],
            provider: contact.cloudProvider,
            setupStatus: contact.setupStatus
          )
        }
      }
      return SignalASIAgentModelSelectionPreparedContent(
        localProfiles: localProfiles,
        cloudContacts: cloudContacts,
        callableTargets: callableTargets
      )
    }.value
    guard !Task.isCancelled, navigationContentGate.isCurrent(generation) else { return }
    preparedContent = prepared
    contentLoading = false
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
      let ready = localProfiles.contains { $0.id == profile.id }
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

    if let target = callableTargets.first(where: { $0.id == targetId }),
       target.kind == .agent {
      return (
        target.title.ifBlank(selection.displayName).ifBlank(target.id),
        AgentConnectorRouteSelector.isDeliverable(target)
          ? t("signalasi.agent.model_selection.on_agent", "Agent")
          : t("signalasi.agent.model_selection.unavailable", "Unavailable")
      )
    }

    if let contact = store.contact(id: targetId) {
      if contact.type == "agent" {
        let title = contact.displayName
          .ifBlank(contact.name)
          .ifBlank(selection.displayName)
          .ifBlank(contact.id)
        let ready = callableTargets
          .first(where: { $0.id == targetId })
          .map { AgentConnectorRouteSelector.isDeliverable($0) }
          ?? false
        return (
          title,
          ready
            ? t("signalasi.agent.model_selection.on_agent", "Agent")
            : t("signalasi.agent.model_selection.unavailable", "Unavailable")
        )
      }

      if let model = selectedCloudModel(in: contact, modelId: selection.modelId) {
        let ready = AgentConnectorAvailability.cloudModelReady(
          model: model,
          apiKey: store.apiKey(for: model),
          provider: contact.cloudProvider,
          setupStatus: contact.setupStatus
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

  private func isSelectedCloud(_ contact: SignalASIContact, model: CloudModelConfig) -> Bool {
    selection.mode == .manual &&
      selection.targetId == contact.id &&
      selection.modelId == model.modelId
  }

  private func selectedCloudModel(in contact: SignalASIContact, modelId: String) -> CloudModelConfig? {
    let cleanModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleanModelId.isEmpty {
      return contact.selectedCloudModel
    }
    return contact.cloudModels.first { $0.modelId == cleanModelId }
  }

  private func isSelectedAgent(_ target: AgentCallableTarget) -> Bool {
    preferredTargetId == target.id
  }

  private func selectAutomatic() {
    AgentModelSelectionSettings.selectAutomatic(for: store.activeAgentConversationId)
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: t("signalasi.agent.model_selection.automatic", "Automatic")
    )
    finishSelection()
  }

  private func selectLocal(_ profile: LocalModelRuntimeProfile) {
    LocalModelRuntimeSettings.setSelectedProfile(profile.id)
    AgentModelSelectionSettings.selectManual(
      for: store.activeAgentConversationId,
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
      for: store.activeAgentConversationId,
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
      for: store.activeAgentConversationId,
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

  private func agentLogoAssetName(for target: AgentCallableTarget) -> String? {
    logoAssetName(for: "\(target.id) \(target.title)")
  }

  private func cloudLogoAssetName(for provider: String) -> String? {
    switch provider.lowercased() {
    case "openai": return "CloudProviderOpenAI"
    case "deepseek": return "CloudProviderDeepSeek"
    case "anthropic", "claude": return "CloudProviderAnthropic"
    case "gemini", "google gemini": return "CloudProviderGemini"
    case "qwen": return "CloudProviderQwen"
    case "openrouter", "open-router": return "CloudProviderOpenRouter"
    default: return nil
    }
  }

  private func logoAssetName(for value: String) -> String? {
    let normalized = value.lowercased()
    if normalized.contains("codex") { return "CodexLogo" }
    if normalized.contains("claude") { return "ClaudeLogo" }
    if normalized.contains("hermes") { return "HermesLogo" }
    return nil
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
