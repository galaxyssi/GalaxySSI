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
  var reasoningEffort: AgentModelReasoningEffort = .automatic

  init(
    mode: AgentModelSelectionMode = .automatic,
    targetId: String = "",
    modelId: String = "",
    displayName: String = "",
    reasoningEffort: AgentModelReasoningEffort = .automatic
  ) {
    self.mode = mode
    self.targetId = targetId
    self.modelId = modelId
    self.displayName = displayName
    self.reasoningEffort = reasoningEffort
  }

  enum CodingKeys: String, CodingKey {
    case mode
    case targetId
    case modelId
    case displayName
    case reasoningEffort
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      mode: try container.decodeIfPresent(AgentModelSelectionMode.self, forKey: .mode) ?? .automatic,
      targetId: try container.decodeIfPresent(String.self, forKey: .targetId) ?? "",
      modelId: try container.decodeIfPresent(String.self, forKey: .modelId) ?? "",
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
      reasoningEffort: try container.decodeIfPresent(
        AgentModelReasoningEffort.self,
        forKey: .reasoningEffort
      ) ?? .automatic
    )
  }
}

enum AgentModelSelectionSettings {
  private static let conversationKeyPrefix = "conversation."
  private static let defaultSelectionKey = "default.selection"
  private static let defaultTargetKeyPrefix = "default.target."
  private static let maxConversationIdLength = 160
  private static let maxTargetIdLength = 160

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
    rememberActiveTarget(for: conversationId, defaults: defaults)
    let automatic = AgentModelSelection()
    save(automatic, for: conversationId, defaults: defaults)
    save(automatic, key: defaultSelectionKey, defaults: defaults)
  }

  static func selectManual(
    for conversationId: String,
    targetId: String,
    modelId: String,
    displayName: String,
    reasoningEffort: AgentModelReasoningEffort = .automatic,
    rememberAsDefault: Bool = true,
    defaults: UserDefaults = .standard
  ) {
    let cleanTargetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTargetId.isEmpty else { return }
    rememberActiveTarget(for: conversationId, defaults: defaults)
    let selection = AgentModelSelection(
      mode: .manual,
      targetId: cleanTargetId,
      modelId: String(modelId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
      displayName: String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
      reasoningEffort: reasoningEffort
    )
    save(selection, for: conversationId, defaults: defaults)
    saveTargetConfiguration(selection, for: conversationId, defaults: defaults)
    if rememberAsDefault {
      save(selection, key: defaultSelectionKey, defaults: defaults)
      saveDefaultTargetConfiguration(selection, defaults: defaults)
    }
  }

  static func inheritDefault(
    for conversationId: String,
    defaults: UserDefaults = .standard
  ) {
    guard !hasStoredSelection(for: conversationId, defaults: defaults) else { return }
    let inherited = loadSelection(key: defaultSelectionKey, defaults: defaults) ?? AgentModelSelection()
    save(inherited, for: conversationId, defaults: defaults)
  }

  static func configurationForTarget(
    conversationId: String,
    targetId: String,
    defaults: UserDefaults = .standard
  ) -> AgentTargetConfiguration? {
    let cleanTargetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTargetId.isEmpty else { return nil }
    let active = selection(for: conversationId, defaults: defaults)
    if active.mode == .manual, active.targetId == cleanTargetId {
      return AgentTargetConfiguration(
        modelId: active.modelId,
        reasoningEffort: active.reasoningEffort
      )
    }
    return loadTargetConfiguration(
      key: targetStorageKey(conversationId: conversationId, targetId: cleanTargetId),
      defaults: defaults
    ) ?? loadTargetConfiguration(
      key: defaultTargetStorageKey(targetId: cleanTargetId),
      defaults: defaults
    )
  }

  static func updateAgentConfiguration(
    for conversationId: String,
    modelId: String,
    reasoningEffort: AgentModelReasoningEffort,
    defaults: UserDefaults = .standard
  ) {
    var current = selection(for: conversationId, defaults: defaults)
    guard current.mode == .manual, !current.targetId.isEmpty else { return }
    current.modelId = String(modelId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    current.reasoningEffort = reasoningEffort
    save(current, for: conversationId, defaults: defaults)
    save(current, key: defaultSelectionKey, defaults: defaults)
    saveTargetConfiguration(current, for: conversationId, defaults: defaults)
    saveDefaultTargetConfiguration(current, defaults: defaults)
  }

  static func clearConversation(
    _ conversationId: String,
    defaults: UserDefaults = .standard
  ) {
    guard let key = storageKey(for: conversationId, field: "selection") else { return }
    defaults.removeObject(forKey: key)
    let prefix = targetStoragePrefix(for: conversationId)
    defaults.dictionaryRepresentation().keys
      .filter { $0.hasPrefix(prefix) }
      .forEach { defaults.removeObject(forKey: $0) }
  }

  static func clearConversations(
    _ conversationIds: Set<String>,
    defaults: UserDefaults = .standard
  ) {
    conversationIds.forEach { clearConversation($0, defaults: defaults) }
  }

  private static func save(
    _ value: AgentModelSelection,
    for conversationId: String,
    defaults: UserDefaults
  ) {
    guard let key = storageKey(for: conversationId, field: "selection") else { return }
    save(value, key: key, defaults: defaults)
  }

  private static func save(
    _ value: AgentModelSelection,
    key: String,
    defaults: UserDefaults
  ) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: key)
  }

  private static func loadSelection(
    key: String,
    defaults: UserDefaults
  ) -> AgentModelSelection? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(AgentModelSelection.self, from: data)
  }

  private static func rememberActiveTarget(
    for conversationId: String,
    defaults: UserDefaults
  ) {
    let current = selection(for: conversationId, defaults: defaults)
    guard current.mode == .manual, !current.targetId.isEmpty else { return }
    saveTargetConfiguration(current, for: conversationId, defaults: defaults)
  }

  private static func saveTargetConfiguration(
    _ selection: AgentModelSelection,
    for conversationId: String,
    defaults: UserDefaults
  ) {
    guard let key = targetStorageKey(conversationId: conversationId, targetId: selection.targetId),
          let data = try? JSONEncoder().encode(
            AgentTargetConfiguration(
              modelId: selection.modelId,
              reasoningEffort: selection.reasoningEffort
            )
          ) else { return }
    defaults.set(data, forKey: key)
  }

  private static func saveDefaultTargetConfiguration(
    _ selection: AgentModelSelection,
    defaults: UserDefaults
  ) {
    guard let key = defaultTargetStorageKey(targetId: selection.targetId),
          let data = try? JSONEncoder().encode(
            AgentTargetConfiguration(
              modelId: selection.modelId,
              reasoningEffort: selection.reasoningEffort
            )
          ) else { return }
    defaults.set(data, forKey: key)
  }

  private static func loadTargetConfiguration(
    key: String?,
    defaults: UserDefaults
  ) -> AgentTargetConfiguration? {
    guard let key, let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(AgentTargetConfiguration.self, from: data)
  }

  private static func storageKey(for conversationId: String, field: String) -> String? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    let scope = String(clean.prefix(maxConversationIdLength))
    return "\(conversationKeyPrefix)\(scope).\(field)"
  }

  private static func targetStoragePrefix(for conversationId: String) -> String {
    guard let key = storageKey(for: conversationId, field: "target") else { return "" }
    return "\(key)."
  }

  private static func targetStorageKey(conversationId: String, targetId: String) -> String? {
    let prefix = targetStoragePrefix(for: conversationId)
    guard !prefix.isEmpty, let encodedTargetId = encodedTargetId(targetId) else { return nil }
    return "\(prefix)\(encodedTargetId).configuration"
  }

  private static func defaultTargetStorageKey(targetId: String) -> String? {
    guard let encodedTargetId = encodedTargetId(targetId) else { return nil }
    return "\(defaultTargetKeyPrefix)\(encodedTargetId).configuration"
  }

  private static func encodedTargetId(_ targetId: String) -> String? {
    let clean = String(targetId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTargetIdLength))
    guard !clean.isEmpty else { return nil }
    return clean.utf8.map { String(format: "%02x", $0) }.joined()
  }
}

struct GalaxySSIAgentModelSelectionPreparedContent {
  var localProfiles: [LocalModelRuntimeProfile]
  var cloudContacts: [GalaxySSIContact]
  var callableTargets: [AgentCallableTarget]
}

struct GalaxySSIAgentModelSelectionView: View {
  private struct ReadyCloudModel: Identifiable {
    var contact: GalaxySSIContact
    var model: CloudModelConfig

    var id: String { "\(contact.id):\(model.modelId)" }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator

  var onSelectionChanged: (() -> Void)?
  @State private var contentLoading = true
  @State private var modelSelectionRefreshToken = UUID()
  @State private var selectionRevision = 0
  @State private var navigationContentGate = GalaxySSINavigationContentGate()
  @State private var preparedContent = GalaxySSIAgentModelSelectionPreparedContent(
    localProfiles: [],
    cloudContacts: [],
    callableTargets: []
  )

  private var selection: AgentModelSelection {
    _ = selectionRevision
    return AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
  }

  private var localProfiles: [LocalModelRuntimeProfile] {
    preparedContent.localProfiles
  }

  private var cloudContacts: [GalaxySSIContact] {
    preparedContent.cloudContacts
  }

  private var readyCloudModels: [ReadyCloudModel] {
    cloudContacts.flatMap { contact in
      CloudModelRequestRoutingPolicy.models(for: contact).compactMap { model in
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
      GalaxySSITopBar(
        title: t("galaxyssi.agent.model_selection.title", "Select model or Agent"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        if contentLoading {
          modelSelectionLoadingContent
        } else {
          VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("galaxyssi.agent.model_selection.hero_title", "Agent model"),
            subtitle: selectionSubtitle,
            systemImage: "cpu.fill",
            tint: .galaxySSIAccent,
            badge: t("galaxyssi.agent.model_selection.badge", "Routing")
          )
          GalaxySSISecuritySectionTitle(
            title: t("galaxyssi.agent.model_selection.routing_section", "ROUTING")
          )
          GalaxySSISecurityActionRow(
            title: t("galaxyssi.agent.model_selection.automatic", "Automatic"),
            subtitle: t(
              "galaxyssi.agent.model_selection.automatic_subtitle",
              "Choose by task, speed, privacy, and availability"
            ),
            systemImage: isAutomatic ? "checkmark.circle.fill" : "arrow.triangle.branch",
            tint: isAutomatic ? .galaxySSIAccent : .galaxySSIInsightText,
            badge: isAutomatic
              ? t("galaxyssi.agent.model_selection.current", "Current")
              : t("galaxyssi.common.select", "Select")
          ) {
            selectAutomatic()
          }

          if selection.mode == .manual,
             let selectedManualTarget,
             !selectedManualTargetIsVisible {
            GalaxySSISecurityStatusRow(
              title: selectedManualTarget.title,
              subtitle: t(
                "galaxyssi.agent.model_selection.unavailable_subtitle",
                "The selected target is currently unavailable. Choose Automatic or another ready target."
              ),
              systemImage: "exclamationmark.triangle.fill",
              tint: .orange,
              badge: t("galaxyssi.agent.model_selection.unavailable", "Unavailable")
            )
          }

          if !localProfiles.isEmpty {
            GalaxySSISecuritySectionTitle(
              title: t("galaxyssi.agent.model_selection.local_section", "ON-DEVICE MODELS")
            )
            GalaxySSISecurityNavigationRow(
              title: t("galaxyssi.settings.local_model", "Local Model Settings"),
              subtitle: t(
                "galaxyssi.settings.local_model.status",
                "Configure on-device inference"
              ),
              systemImage: "arrow.down.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.common.manage", "Manage")
            ) {
              GalaxySSILocalModelLabView()
            }
            ForEach(localProfiles) { profile in
              let selected = isSelectedLocal(profile)
              GalaxySSISecurityActionRow(
                title: profile.displayName,
                subtitle: t(
                  "galaxyssi.agent.model_selection.local_subtitle",
                  "Installed and ready on this iPhone"
                ),
                systemImage: selected ? "checkmark.circle.fill" : "iphone",
                tint: selected ? .galaxySSIAccent : .blue,
                badge: selected
                  ? t("galaxyssi.agent.model_selection.current", "Current")
                  : t("galaxyssi.common.select", "Select"),
                monospacedSubtitle: true
              ) {
                selectLocal(profile)
              }
            }
          } else {
            GalaxySSISecuritySectionTitle(
              title: t("galaxyssi.agent.model_selection.local_section", "ON-DEVICE MODELS")
            )
            GalaxySSISecurityNavigationRow(
              title: t("galaxyssi.settings.local_model", "Local Model Settings"),
              subtitle: t(
                "galaxyssi.agent.model_selection.local_manage_subtitle",
                "Download and prepare an on-device model for private Agent work"
              ),
              systemImage: "arrow.down.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.common.manage", "Manage")
            ) {
              GalaxySSILocalModelLabView()
            }
          }

          if !agentTargets.isEmpty {
            GalaxySSISecuritySectionTitle(
              title: t("galaxyssi.agent.model_selection.agent_section", "AGENTS")
            )
            ForEach(agentTargets) { target in
              let selected = isSelectedAgent(target)
              GalaxySSISecurityActionRow(
                title: target.title,
                subtitle: agentSubtitle(target, selected: selected),
                systemImage: selected ? "checkmark.circle.fill" : "person.2.fill",
                assetImage: agentLogoAssetName(for: target),
                tint: selected ? .galaxySSIAccent : .indigo,
                badge: selected
                  ? t("galaxyssi.agent.model_selection.current", "Current")
                  : t("galaxyssi.common.select", "Select")
              ) {
                selectAgent(target)
              }
              if selected && target.invocationProfile.configurable {
                agentConfigurationView(target)
              }
            }
          }

          GalaxySSISecuritySectionTitle(
            title: t("galaxyssi.agent.model_selection.connect_section", "CONNECT AN AGENT")
          )
          GalaxySSISecurityNavigationRow(
            title: t("galaxyssi.agent.model_selection.scan_agent", "Scan or paste Agent QR"),
            subtitle: t(
              "galaxyssi.agent.model_selection.scan_agent_subtitle",
              "Pair a trusted Desktop Agent or local model through the Android-compatible QR flow"
            ),
            systemImage: "qrcode.viewfinder",
            tint: .orange,
            badge: t("security_scan", "Scan")
          ) {
            AddContactView(autoOpenScanner: true)
          }

          if !readyCloudModels.isEmpty {
            GalaxySSISecuritySectionTitle(
              title: t("galaxyssi.agent.model_selection.cloud_section", "CLOUD MODELS")
            )
            ForEach(readyCloudModels) { item in
              let selected = isSelectedCloud(item.contact, model: item.model)
              GalaxySSISecurityActionRow(
                title: item.model.displayName.ifBlank(item.model.modelId),
                subtitle: "\(item.contact.displayName) - \(item.model.modelId)",
                systemImage: selected ? "checkmark.circle.fill" : "cloud.fill",
                assetImage: cloudLogoAssetName(for: item.contact.cloudProvider),
                tint: selected ? .galaxySSIAccent : cloudModelTint(item.contact.cloudProvider),
                badge: selected
                  ? t("galaxyssi.agent.model_selection.current", "Current")
                  : t("galaxyssi.common.select", "Select"),
                monospacedSubtitle: true
              ) {
                selectCloud(item.contact, model: item.model)
              }
            }
          }

          if localProfiles.isEmpty && agentTargets.isEmpty && readyCloudModels.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.agent.model_selection.no_models", "No ready models"),
              subtitle: t(
                "galaxyssi.agent.model_selection.no_models_subtitle",
                "Configure a cloud model, install a local model, or connect an Agent in Settings."
              ),
              systemImage: "exclamationmark.triangle.fill",
              tint: .orange,
              badge: t("galaxyssi.status.needs_setup", "Needs Setup")
            )
            GalaxySSISecurityNavigationRow(
              title: t("galaxyssi.discover.add_cloud_model", "Add Cloud Model"),
              subtitle: t(
                "galaxyssi.discover.add_cloud_model_subtitle",
                "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"
              ),
              systemImage: "cloud.fill",
              tint: .galaxySSIInsightText,
              badge: t("galaxyssi.common.add", "Add")
            ) {
              CloudModelProviderSelectionView()
            }
            GalaxySSISecurityNavigationRow(
              title: t("galaxyssi.agent_connection.scan_qr", "Scan or Paste Agent QR"),
              subtitle: t(
                "galaxyssi.agent_connection.scan_qr_subtitle",
                "Pair a trusted Desktop Agent or local model through the Android-compatible QR flow"
              ),
              systemImage: "qrcode.viewfinder",
              tint: .orange,
              badge: t("security_scan", "Scan")
            ) {
              AddContactView(autoOpenScanner: true)
            }
          }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIContactImportDidComplete)) { _ in
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIDesktopPairingDidComplete)) { _ in
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentRoutingDidUpdate)) { _ in
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
      GalaxySSISecurityHeroView(
        title: t("galaxyssi.agent.model_selection.hero_title", "Agent model"),
        subtitle: t("cc_loading", "Loading..."),
        systemImage: "cpu.fill",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.agent.model_selection.badge", "Routing")
      )
      HStack(spacing: 10) {
        ProgressView()
          .tint(.galaxySSIAccent)
        Text(t("cc_loading", "Loading..."))
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
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
    if let cached = GalaxySSINavigationContentPrewarm.snapshot(for: store)?.modelSelection,
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
    let fastContent = Self.modelSelectionContent(
      sourceContacts: sourceContacts,
      sourceCloudContacts: sourceCloudContacts,
      apiKeys: apiKeys
    )
    if Self.hasRenderableModelSelectionContent(fastContent) {
      preparedContent = fastContent
      contentLoading = false
    }
    let prepared = await Task.detached(priority: .userInitiated) {
      Self.modelSelectionContent(
        sourceContacts: sourceContacts,
        sourceCloudContacts: sourceCloudContacts,
        apiKeys: apiKeys
      )
    }.value
    guard !Task.isCancelled, navigationContentGate.isCurrent(generation) else { return }
    preparedContent = prepared
    contentLoading = false
  }

  private static func modelSelectionContent(
    sourceContacts: [GalaxySSIContact],
    sourceCloudContacts: [GalaxySSIContact],
    apiKeys: [String: String]
  ) -> GalaxySSIAgentModelSelectionPreparedContent {
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
    return GalaxySSIAgentModelSelectionPreparedContent(
      localProfiles: localProfiles,
      cloudContacts: cloudContacts,
      callableTargets: callableTargets
    )
  }

  private static func hasRenderableModelSelectionContent(
    _ content: GalaxySSIAgentModelSelectionPreparedContent
  ) -> Bool {
    !content.localProfiles.isEmpty ||
      !content.cloudContacts.isEmpty ||
      !content.callableTargets.isEmpty
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
          ? t("galaxyssi.agent.model_selection.on_device", "On device")
          : t("galaxyssi.agent.model_selection.unavailable", "Unavailable")
      )
    }

    if let target = callableTargets.first(where: { $0.id == targetId }),
       target.kind == .agent {
      return (
        target.title.ifBlank(selection.displayName).ifBlank(target.id),
        AgentConnectorRouteSelector.isDeliverable(target)
          ? t("galaxyssi.agent.model_selection.on_agent", "Agent")
          : t("galaxyssi.agent.model_selection.unavailable", "Unavailable")
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
            ? t("galaxyssi.agent.model_selection.on_agent", "Agent")
            : t("galaxyssi.agent.model_selection.unavailable", "Unavailable")
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
            : t("galaxyssi.agent.model_selection.unavailable", "Unavailable")
        )
      }
    }

    return (
      selection.displayName.ifBlank(targetId),
      t("galaxyssi.agent.model_selection.unavailable", "Unavailable")
    )
  }

  private var selectionSubtitle: String {
    selectedManualTarget.map { "\($0.title) - \($0.subtitle)" }
      ?? t("galaxyssi.agent.model_selection.automatic", "Automatic")
  }

  private func isSelectedLocal(_ profile: LocalModelRuntimeProfile) -> Bool {
    selection.mode == .manual &&
      selection.targetId == "local-llm" &&
      selection.modelId == profile.id
  }

  private func isSelectedCloud(_ contact: GalaxySSIContact, model: CloudModelConfig) -> Bool {
    selection.mode == .manual &&
      selection.targetId == contact.id &&
      selection.modelId == model.modelId
  }

  private func selectedCloudModel(in contact: GalaxySSIContact, modelId: String) -> CloudModelConfig? {
    let cleanModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleanModelId.isEmpty {
      return contact.selectedCloudModel
    }
    return CloudModelRequestRoutingPolicy.model(in: contact, modelId: cleanModelId)
  }

  private func isSelectedAgent(_ target: AgentCallableTarget) -> Bool {
    preferredTargetId == target.id
  }

  private func selectAutomatic() {
    AgentModelSelectionSettings.selectAutomatic(for: store.activeAgentConversationId)
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: t("galaxyssi.agent.model_selection.automatic", "Automatic")
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

  private func selectCloud(_ contact: GalaxySSIContact, model: CloudModelConfig) {
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
    let remembered = AgentModelSelectionSettings.configurationForTarget(
      conversationId: store.activeAgentConversationId,
      targetId: target.id
    )
    let rememberedEffort = remembered?.reasoningEffort
    let effort = rememberedEffort.flatMap { value in
      target.invocationProfile.reasoningEfforts.contains(value) ? value : nil
    } ?? target.invocationProfile.reasoningEfforts.first ?? .automatic
    AgentModelSelectionSettings.selectManual(
      for: store.activeAgentConversationId,
      targetId: target.id,
      modelId: target.invocationProfile.normalizedModelId(remembered?.modelId ?? ""),
      displayName: title,
      reasoningEffort: effort
    )
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: title
    )
    selectionRevision += 1
    onSelectionChanged?()
  }

  private func agentSubtitle(_ target: AgentCallableTarget, selected: Bool) -> String {
    var values = [
      t("galaxyssi.agent.model_selection.agent_subtitle", "Connected and ready Agent")
    ]
    if selected, !selection.modelId.isEmpty {
      values.append(
        target.invocationProfile.models.first(where: { $0.id == selection.modelId })?.displayName
          ?? selection.modelId
      )
    }
    if selected, selection.reasoningEffort != .automatic {
      values.append(reasoningEffortLabel(selection.reasoningEffort))
    }
    return values.joined(separator: " · ")
  }

  @ViewBuilder
  private func agentConfigurationView(_ target: AgentCallableTarget) -> some View {
    let profile = target.invocationProfile
    VStack(alignment: .leading, spacing: 10) {
      if !profile.models.isEmpty {
        HStack(spacing: 12) {
          Text(t("galaxyssi.agent.model_selection.model", "Model"))
            .font(.system(size: 13))
            .foregroundColor(.galaxySSITextSecondary)
          Spacer(minLength: 12)
          Menu {
            ForEach(profile.models) { model in
              Button {
                updateAgentConfiguration(
                  modelId: model.id,
                  reasoningEffort: selection.reasoningEffort
                )
              } label: {
                Label(
                  model.displayName,
                  systemImage: selection.modelId == model.id ? "checkmark" : "circle"
                )
              }
            }
          } label: {
            HStack(spacing: 5) {
              Text(selectedModelLabel(profile))
                .lineLimit(1)
              Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
          }
        }
        .frame(minHeight: 40)
      }

      if !profile.reasoningEfforts.isEmpty {
        Text(t("galaxyssi.agent.model_selection.reasoning_effort", "Reasoning effort"))
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
        HStack(spacing: 5) {
          ForEach(profile.reasoningEfforts) { effort in
            Button {
              updateAgentConfiguration(
                modelId: profile.normalizedModelId(selection.modelId),
                reasoningEffort: effort
              )
            } label: {
              Text(reasoningEffortLabel(effort))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(
                  selection.reasoningEffort == effort ? .galaxySSIAccent : .galaxySSITextPrimary
                )
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                  selection.reasoningEffort == effort
                    ? Color.galaxySSIAccent.opacity(0.12)
                    : Color.galaxySSITextSecondary.opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
      }

      Text(t("galaxyssi.agent.model_selection.current_session", "Saved for this Agent and future sessions"))
        .font(.system(size: 11))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .padding(.leading, 54)
    .padding(.trailing, 6)
    .padding(.bottom, 12)
  }

  private func selectedModelLabel(_ profile: AgentInvocationProfile) -> String {
    let modelId = profile.normalizedModelId(selection.modelId)
    return profile.models.first(where: { $0.id == modelId })?.displayName ?? modelId
  }

  private func updateAgentConfiguration(
    modelId: String,
    reasoningEffort: AgentModelReasoningEffort
  ) {
    AgentModelSelectionSettings.updateAgentConfiguration(
      for: store.activeAgentConversationId,
      modelId: modelId,
      reasoningEffort: reasoningEffort
    )
    selectionRevision += 1
    onSelectionChanged?()
  }

  private func reasoningEffortLabel(_ effort: AgentModelReasoningEffort) -> String {
    switch effort {
    case .automatic:
      return t("galaxyssi.agent.model_selection.reasoning.auto", "Auto")
    case .low:
      return t("galaxyssi.agent.model_selection.reasoning.low", "Low")
    case .medium:
      return t("galaxyssi.agent.model_selection.reasoning.medium", "Medium")
    case .high:
      return t("galaxyssi.agent.model_selection.reasoning.high", "High")
    case .xhigh:
      return t("galaxyssi.agent.model_selection.reasoning.xhigh", "Extra high")
    }
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
    default: return .galaxySSIInsightText
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
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
