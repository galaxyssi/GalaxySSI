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
    self.modelId = RetiredAgentModelPolicy.availableOrDefault(modelId)
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
    selectAutomaticForConversation(for: conversationId, defaults: defaults)
    save(AgentModelSelection(), key: defaultSelectionKey, defaults: defaults)
  }

  static func selectAutomaticForConversation(
    for conversationId: String,
    defaults: UserDefaults = .standard
  ) {
    rememberActiveTarget(for: conversationId, defaults: defaults)
    save(AgentModelSelection(), for: conversationId, defaults: defaults)
  }

  static func defaultSelection(defaults: UserDefaults = .standard) -> AgentModelSelection {
    AgentModelSelection()
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
    let inherited = defaultSelection(defaults: defaults)
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
    if defaults.data(forKey: key) != data { AgentInvocationProfile.clearMetadataCache() }
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
  private typealias ReadyCloudModel = AgentModelPickerCloudChoice

  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator

  var onSelectionChanged: (() -> Void)?
  @State private var contentLoading = true
  @State private var preparedConversationId = ""
  @State private var preparedIdentityFingerprint = ""
  @State private var pickerVisible = false
  @State private var bypassPreparedCache = false
  @State private var contentLoadInFlight = false
  @State private var reloadPending = false
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
    AgentModelPickerPolicy.desktopTargets(callableTargets, selectedId: selection.targetId)
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
        trailing: {
          GalaxySSIAndroidIconButton(systemName: "arrow.clockwise") {
            bypassPreparedCache = true
            modelSelectionRefreshToken = UUID()
            _ = coordinator.requestCapabilityManifestRefresh(force: true)
          }
          .accessibilityLabel(Text(t("agent_model_picker.retry", "Reload models")))
          .accessibilityIdentifier("ios.agent.model-picker.reload")
        }
      )
      if contentLoading {
        modelSelectionLoadingContent
      } else {
        GalaxySSIAgentModelPickerContent(
          conversationId: store.activeAgentConversationId,
          selection: selection,
          localProfiles: localProfiles,
          agents: agentTargets,
          clouds: readyCloudModels,
          currentDetail: selectionSubtitle,
          manualAvailable: selectedManualTargetIsVisible,
          remembersNewChats: AgentModelSelectionSettings.defaultSelection() == selection,
          onAutomatic: selectAutomatic,
          onLocal: selectLocal,
          onCloud: { selectCloud($0.contact, model: $0.model) },
          onAgent: { selectAgent($0, modelId: $1) },
          onEffort: { updateAgentConfiguration(modelId: $0, reasoningEffort: $1) },
          agentLogo: agentLogoAssetName,
          cloudLogo: cloudLogoAssetName,
          effortLabel: reasoningEffortLabel
        )
        .id(store.activeAgentConversationId)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      pickerVisible = true
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIContactImportDidComplete)) { _ in
      guard pickerVisible else { return }
      bypassPreparedCache = true
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIDesktopPairingDidComplete)) { _ in
      guard pickerVisible else { return }
      bypassPreparedCache = true
      contentLoading = true
      modelSelectionRefreshToken = UUID()
      _ = coordinator.requestCapabilityManifestRefresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentRoutingDidUpdate)) { _ in
      guard pickerVisible else { return }
      bypassPreparedCache = true
      modelSelectionRefreshToken = UUID()
    }
    .onDisappear {
      pickerVisible = false
      reloadPending = false
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
    return "\(store.profile.identityFingerprint)|\(store.activeAgentConversationId)|\(contacts)"
  }

  private func prepareModelSelectionContent() async {
    guard pickerVisible, !Task.isCancelled else { return }
    guard !contentLoadInFlight else { reloadPending = true; return }
    contentLoadInFlight = true
    defer {
      contentLoadInFlight = false
      if reloadPending && pickerVisible {
        reloadPending = false
        modelSelectionRefreshToken = UUID()
      }
    }
    let generation = navigationContentGate.begin()
    let conversationId = store.activeAgentConversationId
    let identityFingerprint = store.profile.identityFingerprint
    if !bypassPreparedCache,
       let cached = GalaxySSINavigationContentPrewarm.snapshot(for: store)?.modelSelection,
       !Task.isCancelled {
      preparedContent = cached
      preparedConversationId = conversationId
      preparedIdentityFingerprint = identityFingerprint
      contentLoading = false
      return
    }
    bypassPreparedCache = false
    if preparedConversationId != conversationId { contentLoading = true }
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
      Self.modelSelectionContent(
        sourceContacts: sourceContacts,
        sourceCloudContacts: sourceCloudContacts,
        apiKeys: apiKeys
      )
    }.value
    guard !Task.isCancelled, navigationContentGate.isCurrent(generation), pickerVisible,
          store.activeAgentConversationId == conversationId,
          store.profile.identityFingerprint == identityFingerprint else { return }
    preparedContent = prepared
    preparedConversationId = conversationId
    preparedIdentityFingerprint = identityFingerprint
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

  private func selectedCloudModel(in contact: GalaxySSIContact, modelId: String) -> CloudModelConfig? {
    let cleanModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleanModelId.isEmpty {
      return contact.selectedCloudModel
    }
    return CloudModelRequestRoutingPolicy.model(in: contact, modelId: cleanModelId)
  }

  private func selectAutomatic() {
    guard canSelectPreparedContent else { return }
    AgentModelSelectionSettings.selectAutomatic(for: store.activeAgentConversationId)
    store.setAgentSessionSelectedModelOrAgent(
      id: store.activeAgentConversationId,
      label: t("galaxyssi.agent.model_selection.automatic", "Automatic")
    )
    finishSelection()
  }

  private func selectLocal(_ profile: LocalModelRuntimeProfile) {
    guard canSelectPreparedContent, LocalModelRuntimeSettings.activeProfiles().contains(where: { $0.id == profile.id }) else { return }
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
    guard canSelectPreparedContent, let current = store.contact(id: contact.id),
          let currentModel = CloudModelRequestRoutingPolicy.model(in: current, modelId: model.modelId),
          AgentConnectorAvailability.cloudModelReady(model: currentModel, apiKey: store.apiKey(for: currentModel),
            provider: current.cloudProvider, setupStatus: current.setupStatus) else { return }
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

  private func selectAgent(_ target: AgentCallableTarget, modelId: String? = nil) {
    guard canSelectPreparedContent,
          let current = AgentCallableTargetCatalog.build(contacts: store.visibleContacts,
            apiKey: { store.apiKey(for: $0) }).first(where: { $0.id == target.id }),
          AgentConnectorRouteSelector.isDeliverable(current),
          modelId == nil || (modelId == "" && current.invocationProfile.models.isEmpty) ||
            current.invocationProfile.models.contains(where: { $0.id == modelId }) else { return }
    let target = current
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
      modelId: target.invocationProfile.normalizedModelId(modelId ?? remembered?.modelId ?? ""),
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

  private func updateAgentConfiguration(
    modelId: String,
    reasoningEffort: AgentModelReasoningEffort
  ) {
    guard canSelectPreparedContent,
          let current = AgentCallableTargetCatalog.build(contacts: store.visibleContacts,
            apiKey: { store.apiKey(for: $0) }).first(where: { $0.id == selection.targetId }),
          AgentConnectorRouteSelector.isDeliverable(current),
          current.invocationProfile.reasoningEfforts.contains(reasoningEffort),
          current.invocationProfile.models.isEmpty || current.invocationProfile.models.contains(where: { $0.id == modelId })
    else { return }
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

  private var canSelectPreparedContent: Bool {
    pickerVisible && !contentLoading && preparedConversationId == store.activeAgentConversationId &&
      preparedIdentityFingerprint == store.profile.identityFingerprint
  }

  private func finishSelection() {
    selectionRevision += 1
    onSelectionChanged?()
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
