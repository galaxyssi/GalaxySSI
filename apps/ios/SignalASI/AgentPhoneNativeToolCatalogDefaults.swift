import Foundation

extension AgentPhoneNativeToolCatalog {
  static func defaultRegistry(
    workspaceStore: AgentWorkspaceNativeToolExecutor = AgentWorkspaceNativeToolExecutor(),
    actionExecutor: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses(),
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
    return try createRegistry(
      workspaceStore: workspaceStore,
      actionExecutor: actionExecutor,
      screenProvider: screenProvider,
      capabilityStatuses: capabilityStatuses,
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
    workspaceStore: AgentWorkspaceNativeToolExecutor = AgentWorkspaceNativeToolExecutor(),
    actionExecutor: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses(),
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
      capabilityStatuses: capabilityStatuses,
      storageRootURL: storageRootURL,
      fileManager: fileManager,
      nowMillis: nowMillis
    )
  }
}
