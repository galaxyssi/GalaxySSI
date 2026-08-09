import Foundation

struct AgentPhoneNativeToolRuntime {
  var registry: AgentNativeToolRegistry
  var actionExecutor: AgentActionExecutor
  var nativeActionExecutor: AgentNativeToolActionExecutor

  init(
    registry: AgentNativeToolRegistry,
    actionExecutor: AgentActionExecutor,
    nativeActionExecutor: AgentNativeToolActionExecutor
  ) {
    self.registry = registry
    self.actionExecutor = actionExecutor
    self.nativeActionExecutor = nativeActionExecutor
  }
}

extension AgentPhoneNativeToolCatalog {
  static func defaultRuntime(
    workspaceStore: AgentWorkspaceNativeToolExecutor? = nil,
    actionExecutor: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus] = {
      AgentPhoneCapabilityCatalog.declaredStatuses()
    },
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL(),
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    guardSideEffects: Bool = true,
    actionNotificationPublisher: AgentActionNotificationPublishing? = nil,
    nativeToolEventSink: AgentNativeToolLifecycleEventSink = .none,
    homeAssistantSettingsProvider: @escaping () -> HomeAssistantSettings = { .default },
    homeAssistantProvider: AgentIOSHomeAssistantToolProviding? = nil,
    notificationProvider: AgentIOSNotificationToolProviding = AgentIOSOwnedNotificationToolProvider(),
    visibleCaptureProvider: AgentIOSVisibleCaptureToolProviding = AgentIOSForegroundVisibleCaptureProvider(),
    webMediaProvider: AgentIOSWebMediaToolProviding = AgentIOSURLSessionWebMediaToolProvider(),
    webIntelligenceProvider: AgentIOSWebIntelligenceToolProviding = AgentIOSUnavailableWebIntelligenceToolProvider(),
    mediaProvider: AgentIOSMediaNativeToolProviding = AgentIOSUnavailableMediaNativeToolProvider(),
    selfEvolutionProvider: AgentIOSSelfEvolutionToolProviding = AgentIOSUnavailableSelfEvolutionToolProvider(),
    desktopRemoteProvider: AgentIOSDesktopRemoteToolProviding = AgentIOSUnavailableDesktopRemoteToolProvider(),
    mcpProvider: AgentIOSMcpNativeToolProviding = AgentIOSUnavailableMcpNativeToolProvider(),
    onDeviceRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding = AgentIOSUnavailableOnDeviceRuntimeToolProvider()
  ) throws -> AgentPhoneNativeToolRuntime {
    let registry = try defaultRegistry(
      workspaceStore: workspaceStore,
      actionExecutor: actionExecutor,
      screenProvider: screenProvider,
      capabilityStatusProvider: capabilityStatusProvider,
      storageRootURL: storageRootURL,
      fileManager: fileManager,
      nowMillis: nowMillis,
      homeAssistantSettingsProvider: homeAssistantSettingsProvider,
      homeAssistantProvider: homeAssistantProvider,
      notificationProvider: notificationProvider,
      visibleCaptureProvider: visibleCaptureProvider,
      webMediaProvider: webMediaProvider,
      webIntelligenceProvider: webIntelligenceProvider,
      mediaProvider: mediaProvider,
      selfEvolutionProvider: selfEvolutionProvider,
      desktopRemoteProvider: desktopRemoteProvider,
      mcpProvider: mcpProvider,
      onDeviceRuntimeProvider: onDeviceRuntimeProvider
    )
    let nativeActionExecutor = AgentNativeToolActionExecutor(
      registry: registry,
      delegate: actionExecutor,
      nowMillis: nowMillis,
      eventSink: nativeToolEventSink
    )
    let notifyingActionExecutor = NotifyingAgentActionExecutor(
      delegate: nativeActionExecutor,
      notifications: AgentActionNotificationCenter(
        publisher: actionNotificationPublisher ?? AgentIOSUserNotificationPublisher(),
        nowMillis: nowMillis
      )
    )
    let resolvedActionExecutor: AgentActionExecutor = guardSideEffects
      ? PhoneExecutionAuthority.guarded(notifyingActionExecutor)
      : notifyingActionExecutor
    return AgentPhoneNativeToolRuntime(
      registry: registry,
      actionExecutor: resolvedActionExecutor,
      nativeActionExecutor: nativeActionExecutor
    )
  }

  static func defaultRegistry(
    workspaceStore: AgentWorkspaceNativeToolExecutor? = nil,
    actionExecutor: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus] = {
      AgentPhoneCapabilityCatalog.declaredStatuses()
    },
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL(),
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    homeAssistantSettingsProvider: @escaping () -> HomeAssistantSettings = { .default },
    homeAssistantProvider: AgentIOSHomeAssistantToolProviding? = nil,
    notificationProvider: AgentIOSNotificationToolProviding = AgentIOSOwnedNotificationToolProvider(),
    visibleCaptureProvider: AgentIOSVisibleCaptureToolProviding = AgentIOSForegroundVisibleCaptureProvider(),
    webMediaProvider: AgentIOSWebMediaToolProviding = AgentIOSURLSessionWebMediaToolProvider(),
    webIntelligenceProvider: AgentIOSWebIntelligenceToolProviding = AgentIOSUnavailableWebIntelligenceToolProvider(),
    mediaProvider: AgentIOSMediaNativeToolProviding = AgentIOSUnavailableMediaNativeToolProvider(),
    selfEvolutionProvider: AgentIOSSelfEvolutionToolProviding = AgentIOSUnavailableSelfEvolutionToolProvider(),
    desktopRemoteProvider: AgentIOSDesktopRemoteToolProviding = AgentIOSUnavailableDesktopRemoteToolProvider(),
    mcpProvider: AgentIOSMcpNativeToolProviding = AgentIOSUnavailableMcpNativeToolProvider(),
    onDeviceRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding = AgentIOSUnavailableOnDeviceRuntimeToolProvider()
  ) throws -> AgentNativeToolRegistry {
    let stores = AgentNativeToolDefaultStores.makePersistentStores(
      rootURL: storageRootURL,
      fileManager: fileManager,
      nowMillis: nowMillis
    )
    let resolvedWorkspaceStore = workspaceStore ?? AgentWorkspaceNativeToolExecutor(
      nowMillis: nowMillis,
      stateStore: stores.workspaceStateStore
    )
    let resolvedHomeAssistantProvider = homeAssistantProvider ?? AgentIOSConfiguredHomeAssistantToolProvider(
      settingsProvider: homeAssistantSettingsProvider
    )
    let resolvedOnDeviceRuntimeProvider = defaultOnDeviceRuntimeProvider(
      onDeviceRuntimeProvider,
      runtimeRootURL: AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(storageRootURL: storageRootURL),
      fileManager: fileManager,
      nowMillis: nowMillis
    )
    let resolvedSelfEvolutionProvider = defaultSelfEvolutionProvider(
      selfEvolutionProvider,
      storeFileURL: AgentIOSFileSelfEvolutionTaskStore.defaultFileURL(storageRootURL: storageRootURL),
      runtimeProvider: resolvedOnDeviceRuntimeProvider,
      fileManager: fileManager,
      nowMillis: nowMillis
    )
    return try createRegistry(
      workspaceStore: resolvedWorkspaceStore,
      actionExecutor: actionExecutor,
      screenProvider: screenProvider,
      capabilityStatusProvider: capabilityStatusProvider,
      replayStore: stores.replayStore,
      auditStore: stores.auditStore,
      nowMillis: nowMillis,
      homeAssistantProvider: resolvedHomeAssistantProvider,
      notificationProvider: notificationProvider,
      visibleCaptureProvider: visibleCaptureProvider,
      webMediaProvider: webMediaProvider,
      webIntelligenceProvider: webIntelligenceProvider,
      mediaProvider: mediaProvider,
      selfEvolutionProvider: resolvedSelfEvolutionProvider,
      desktopRemoteProvider: desktopRemoteProvider,
      mcpProvider: mcpProvider,
      mcpPackageRootURL: AgentIOSMcpClientNativeProvider.defaultPackageRootURL(storageRootURL: storageRootURL),
      mcpAuditStore: FileAgentMcpAuditStore(
        fileURL: AgentIOSMcpClientNativeProvider.defaultAuditFileURL(storageRootURL: storageRootURL),
        fileManager: fileManager
      ),
      onDeviceRuntimeProvider: resolvedOnDeviceRuntimeProvider
    )
  }

  static func createDefault(
    workspaceStore: AgentWorkspaceNativeToolExecutor? = nil,
    actionExecutor: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus] = {
      AgentPhoneCapabilityCatalog.declaredStatuses()
    },
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL(),
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    homeAssistantSettingsProvider: @escaping () -> HomeAssistantSettings = { .default }
  ) throws -> AgentNativeToolRegistry {
    try defaultRegistry(
      workspaceStore: workspaceStore,
      actionExecutor: actionExecutor,
      screenProvider: screenProvider,
      capabilityStatusProvider: capabilityStatusProvider,
      storageRootURL: storageRootURL,
      fileManager: fileManager,
      nowMillis: nowMillis,
      homeAssistantSettingsProvider: homeAssistantSettingsProvider
    )
  }
}
