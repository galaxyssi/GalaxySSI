import Foundation

extension AgentPhoneNativeToolCatalog {
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
    homeAssistantProvider: AgentIOSHomeAssistantToolProviding = AgentIOSUnavailableHomeAssistantToolProvider(),
    notificationProvider: AgentIOSNotificationToolProviding = AgentIOSUnavailableNotificationToolProvider(),
    visibleCaptureProvider: AgentIOSVisibleCaptureToolProviding = AgentIOSUnavailableVisibleCaptureToolProvider(),
    webMediaProvider: AgentIOSWebMediaToolProviding = AgentIOSUnavailableWebMediaToolProvider(),
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
    return try createRegistry(
      workspaceStore: resolvedWorkspaceStore,
      actionExecutor: actionExecutor,
      screenProvider: screenProvider,
      capabilityStatusProvider: capabilityStatusProvider,
      replayStore: stores.replayStore,
      auditStore: stores.auditStore,
      nowMillis: nowMillis,
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
    }
  ) throws -> AgentNativeToolRegistry {
    try defaultRegistry(
      workspaceStore: workspaceStore,
      actionExecutor: actionExecutor,
      screenProvider: screenProvider,
      capabilityStatusProvider: capabilityStatusProvider,
      storageRootURL: storageRootURL,
      fileManager: fileManager,
      nowMillis: nowMillis
    )
  }
}
