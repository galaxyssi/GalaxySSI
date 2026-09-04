import Foundation

enum AgentPhoneNativeToolCatalog {
  static let workspaceInitialize = "galaxyssi.workspace.initialize"
  static let workspaceMkdir = "galaxyssi.workspace.directory.create"
  static let workspaceList = "galaxyssi.workspace.directory.list"
  static let workspaceStat = "galaxyssi.workspace.file.stat"
  static let workspaceReadText = "galaxyssi.workspace.file.read.text"
  static let workspaceReadBytes = "galaxyssi.workspace.file.read.bytes"
  static let workspaceWriteText = "galaxyssi.workspace.file.write.text"
  static let workspaceWriteTextBatch = "galaxyssi.workspace.files.write.text.batch"
  static let workspaceCreateText = "galaxyssi.workspace.file.create.text"
  static let workspaceAppendText = "galaxyssi.workspace.file.append.text"
  static let workspaceWriteBytes = "galaxyssi.workspace.file.write.bytes"
  static let workspaceCreateBytes = "galaxyssi.workspace.file.create.bytes"
  static let workspaceAppendBytes = "galaxyssi.workspace.file.append.bytes"
  static let workspaceMove = "galaxyssi.workspace.entry.move"
  static let workspaceCopy = "galaxyssi.workspace.entry.copy"
  static let workspaceDelete = "galaxyssi.workspace.entry.delete"
  static let workspaceSearchText = "galaxyssi.workspace.file.search.text"
  static let workspaceApplyExactPatch = "galaxyssi.workspace.file.patch.exact"
  static let workspaceDiffSummary = "galaxyssi.workspace.file.diff.summary"
  static let workspaceSha256 = "galaxyssi.workspace.file.sha256"
  static let workspaceZipCreate = "galaxyssi.workspace.zip.create"
  static let workspaceZipList = "galaxyssi.workspace.zip.list"
  static let workspaceZipExtract = "galaxyssi.workspace.zip.extract"

  static let workspacePrivatePermission = "galaxyssi.scope.app_private_workspace"
  static let workspaceReadConsent = "galaxyssi.consent.workspace_read"
  static let workspaceWriteConsent = "galaxyssi.consent.workspace_write"

  static let version = "1.0.0"
  static let fileExecutorId = "galaxyssi.workspace_file_tools"
  static let actionExecutorId = "galaxyssi.ios_agent_action"
  static let descriptorExecutorId = "galaxyssi.ios_native_catalog"

  static let supportedActionKinds: [AgentActionKind] = [
    .readScreen,
    .tap,
    .typeText,
    .swipe,
    .longPress,
    .deleteText,
    .pasteText,
    .copyScreenText,
    .back,
    .home,
    .recents,
    .lockScreen,
    .openApp,
    .openURL,
    .setAlarm,
    .replyNotification
  ]

  static let toolIds: Set<String> = Set(workspaceToolIds + supportedActionKinds.map {
    AgentNativeToolAgentActionAdapter.defaultToolId($0)
  })
    .union(AgentIOSSystemNativeToolCatalog.toolIds)
    .union(AgentIOSHardwareNativeToolCatalog.toolIds)
    .union(AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    .union(AgentIOSNotificationNativeToolCatalog.toolIds)
    .union(AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    .union(AgentIOSWebMediaNativeToolCatalog.toolIds)
    .union(AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    .union(AgentIOSMediaNativeToolCatalog.toolIds)
    .union(AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    .union(AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    .union(AgentMcpNativeTools.toolIds)
    .union(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    .union(AgentIOSProjectRepositoryReadToolCatalog.toolIds)
    .union(AgentIOSProjectRepositoryMutationToolCatalog.toolIds)

  static let defaultToolIds: Set<String> = toolIds
    .union(AgentPhoneCapabilityNativeCoverage.coveredToolIds)
    .union(AgentIOSWebMediaNativeToolCatalog.toolIds)
    .union(AgentIOSMediaNativeToolCatalog.toolIds)
    .union(AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    .union(AgentIOSSystemNativeToolCatalog.toolIds)
    .union(AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    .union(AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    .union(AgentMcpNativeTools.toolIds)
    .union(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)

  static func definitions(
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses()
  ) -> [AgentPhoneNativeToolDefinition] {
    definitions(capabilityStatusProvider: { capabilityStatuses })
  }

  static func definitions(
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus],
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) -> [AgentPhoneNativeToolDefinition] {
    let resolvedWebMediaProvider = AgentIOSURLSessionWebMediaToolProvider()
    let resolvedWebIntelligenceProvider = defaultCatalogWebIntelligenceProvider(
      webMediaProvider: resolvedWebMediaProvider,
      nowMillis: nowMillis
    )
    let resolvedMediaProvider = defaultCatalogMediaProvider(nowMillis: nowMillis)
    let resolvedOnDeviceRuntimeProvider = defaultOnDeviceRuntimeProvider(
      AgentIOSUnavailableOnDeviceRuntimeToolProvider(),
      nowMillis: nowMillis
    )
    let resolvedSelfEvolutionProvider = defaultSelfEvolutionProvider(
      AgentIOSUnavailableSelfEvolutionToolProvider(),
      runtimeProvider: resolvedOnDeviceRuntimeProvider,
      nowMillis: nowMillis
    )
    let resolvedMcpProvider = defaultMcpProvider(
      AgentIOSUnavailableMcpNativeToolProvider(),
      nowMillis: nowMillis
    )
    return workspaceDefinitions() +
      actionDefinitions(capabilityStatusProvider: capabilityStatusProvider, nowMillis: nowMillis) +
      AgentIOSSystemNativeToolCatalog.definitions() +
      AgentIOSHardwareNativeToolCatalog.definitions() +
      AgentIOSHomeAssistantNativeToolCatalog.definitions() +
      AgentIOSNotificationNativeToolCatalog.definitions() +
      AgentIOSVisibleCaptureNativeToolCatalog.definitions() +
      AgentIOSWebMediaNativeToolCatalog.definitions(provider: resolvedWebMediaProvider) +
      AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: resolvedWebIntelligenceProvider) +
      AgentIOSMediaNativeToolCatalog.definitions(provider: resolvedMediaProvider) +
      AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: resolvedSelfEvolutionProvider) +
      AgentIOSDesktopRemoteNativeToolCatalog.definitions() +
      AgentMcpNativeTools.definitions(provider: resolvedMcpProvider) +
      AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: resolvedOnDeviceRuntimeProvider) +
      AgentIOSProjectRepositoryReadToolCatalog.definitions(runtimeProvider: resolvedOnDeviceRuntimeProvider) +
      AgentIOSProjectRepositoryMutationToolCatalog.definitions(runtimeProvider: resolvedOnDeviceRuntimeProvider)
  }

  static func descriptors(
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses()
  ) -> [AgentNativeToolDescriptor] {
    definitions(capabilityStatuses: capabilityStatuses).map(\.descriptor)
  }

  static func descriptors(
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus],
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) -> [AgentNativeToolDescriptor] {
    definitions(capabilityStatusProvider: capabilityStatusProvider, nowMillis: nowMillis).map(\.descriptor)
  }

  static func createRegistry(
    workspaceStore: AgentWorkspaceNativeToolExecutor = AgentWorkspaceNativeToolExecutor(),
    actionExecutor: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus] = {
      AgentPhoneCapabilityCatalog.declaredStatuses()
    },
    replayStore: AgentNativeToolReplayStore = InMemoryAgentNativeToolReplayStore(),
    auditStore: AgentNativeToolAuditStore = InMemoryAgentNativeToolAuditStore(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    homeAssistantProvider: AgentIOSHomeAssistantToolProviding = AgentIOSConfiguredHomeAssistantToolProvider(),
    notificationProvider: AgentIOSNotificationToolProviding = AgentIOSOwnedNotificationToolProvider(),
    visibleCaptureProvider: AgentIOSVisibleCaptureToolProviding = AgentIOSForegroundVisibleCaptureProvider(),
    webMediaProvider: AgentIOSWebMediaToolProviding = AgentIOSURLSessionWebMediaToolProvider(),
    webIntelligenceProvider: AgentIOSWebIntelligenceToolProviding = AgentIOSUnavailableWebIntelligenceToolProvider(),
    mediaProvider: AgentIOSMediaNativeToolProviding = AgentIOSUnavailableMediaNativeToolProvider(),
    selfEvolutionProvider: AgentIOSSelfEvolutionToolProviding = AgentIOSUnavailableSelfEvolutionToolProvider(),
    desktopRemoteProvider: AgentIOSDesktopRemoteToolProviding = AgentIOSUnavailableDesktopRemoteToolProvider(),
    mcpProvider: AgentIOSMcpNativeToolProviding = AgentIOSUnavailableMcpNativeToolProvider(),
    mcpPackageRootURL: URL? = nil,
    mcpAuditStore: AgentMcpAuditStore = InMemoryAgentMcpAuditStore(),
    onDeviceRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding = AgentIOSUnavailableOnDeviceRuntimeToolProvider()
  ) throws -> AgentNativeToolRegistry {
    let registry = try AgentNativeToolRegistry(
      replayStore: replayStore,
      auditStore: auditStore,
      nowMillis: nowMillis
    )
    let resolvedOnDeviceRuntimeProvider = defaultOnDeviceRuntimeProvider(
      onDeviceRuntimeProvider,
      nowMillis: nowMillis
    )
    let resolvedMediaProvider = defaultMediaProvider(
      mediaProvider: mediaProvider,
      onDeviceRuntimeProvider: resolvedOnDeviceRuntimeProvider,
      nowMillis: nowMillis
    )
    let resolvedWebIntelligenceProvider = defaultWebIntelligenceProvider(
      webIntelligenceProvider,
      webMediaProvider: webMediaProvider,
      nowMillis: nowMillis
    )
    let resolvedNotificationProvider = defaultNotificationProvider(notificationProvider)
    let resolvedSelfEvolutionProvider = defaultSelfEvolutionProvider(
      selfEvolutionProvider,
      runtimeProvider: resolvedOnDeviceRuntimeProvider,
      nowMillis: nowMillis
    )
    let resolvedMcpProvider = defaultMcpProvider(
      mcpProvider,
      packageRootURL: mcpPackageRootURL,
      auditStore: mcpAuditStore,
      nowMillis: nowMillis
    )
    let executables =
      workspaceExecutableDefinitions(store: workspaceStore) +
      actionExecutableDefinitions(
        delegate: actionExecutor,
        screenProvider: screenProvider,
        capabilityStatusProvider: capabilityStatusProvider,
        nowMillis: nowMillis
      ) +
      systemExecutableDefinitions() +
      hardwareExecutableDefinitions() +
      homeAssistantExecutableDefinitions(provider: homeAssistantProvider, nowMillis: nowMillis) +
      notificationExecutableDefinitions(provider: resolvedNotificationProvider, nowMillis: nowMillis) +
      visibleCaptureExecutableDefinitions(provider: visibleCaptureProvider) +
      webMediaExecutableDefinitions(provider: webMediaProvider) +
      webIntelligenceExecutableDefinitions(provider: resolvedWebIntelligenceProvider) +
      mediaExecutableDefinitions(provider: resolvedMediaProvider, nowMillis: nowMillis) +
      selfEvolutionExecutableDefinitions(provider: resolvedSelfEvolutionProvider, nowMillis: nowMillis) +
      desktopRemoteExecutableDefinitions(provider: desktopRemoteProvider) +
      mcpExecutableDefinitions(provider: resolvedMcpProvider) +
      onDeviceRuntimeExecutableDefinitions(provider: resolvedOnDeviceRuntimeProvider) +
      projectRepositoryReadExecutableDefinitions(runtimeProvider: resolvedOnDeviceRuntimeProvider) +
      projectRepositoryMutationExecutableDefinitions(runtimeProvider: resolvedOnDeviceRuntimeProvider)
    return try registry.registerExecutables(executables)
  }

  static func workspaceExecutableDefinitions(
    store: AgentWorkspaceNativeToolExecutor = AgentWorkspaceNativeToolExecutor()
  ) -> [AgentNativeToolExecutableDefinition] {
    workspaceDefinitions().map(store.executableDefinition)
  }

  static func systemExecutableDefinitions(
    executor: AgentIOSSystemNativeToolExecutor = AgentIOSSystemNativeToolExecutor()
  ) -> [AgentNativeToolExecutableDefinition] {
    AgentIOSSystemNativeToolCatalog.definitions()
      .filter { AgentIOSSystemNativeToolCatalog.executableToolIds.contains($0.id) }
      .map(executor.executableDefinition)
  }

  static func hardwareExecutableDefinitions(
    executor: AgentIOSHardwareNativeToolExecutor = AgentIOSHardwareNativeToolExecutor()
  ) -> [AgentNativeToolExecutableDefinition] {
    AgentIOSHardwareNativeToolCatalog.definitions()
      .filter { AgentIOSHardwareNativeToolCatalog.executableToolIds.contains($0.id) }
      .map(executor.executableDefinition)
  }

  static func homeAssistantExecutableDefinitions(
    provider: AgentIOSHomeAssistantToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSHomeAssistantNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSHomeAssistantNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func notificationExecutableDefinitions(
    provider: AgentIOSNotificationToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSNotificationNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSNotificationNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func visibleCaptureExecutableDefinitions(
    provider: AgentIOSVisibleCaptureToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSVisibleCaptureNativeToolExecutor(provider: provider)
    return AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func webIntelligenceExecutableDefinitions(
    provider: AgentIOSWebIntelligenceToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSWebIntelligenceNativeToolExecutor(provider: provider)
    return AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func webMediaExecutableDefinitions(
    provider: AgentIOSWebMediaToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSWebMediaNativeToolExecutor(provider: provider)
    return AgentIOSWebMediaNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func mediaExecutableDefinitions(
    provider: AgentIOSMediaNativeToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSMediaNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSMediaNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  private static func defaultMediaProvider(
    mediaProvider: AgentIOSMediaNativeToolProviding,
    onDeviceRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding,
    nowMillis: @escaping () -> Int64
  ) -> AgentIOSMediaNativeToolProviding {
    guard mediaProvider is AgentIOSUnavailableMediaNativeToolProvider else {
      return mediaProvider
    }
    return AgentIOSSignedFfmpegMediaProvider(
      runtime: AgentIOSOnDeviceFfmpegRuntimeAdapter(provider: onDeviceRuntimeProvider, nowMillis: nowMillis),
      passthroughProvider: defaultCatalogMediaProvider(nowMillis: nowMillis),
      nowMillis: nowMillis
    )
  }

  private static func defaultCatalogMediaProvider(
    nowMillis: @escaping () -> Int64
  ) -> AgentIOSMediaNativeToolProviding {
    AgentIOSAVFoundationMediaProvider(nowMillis: nowMillis)
  }

  private static func defaultWebIntelligenceProvider(
    _ provider: AgentIOSWebIntelligenceToolProviding,
    webMediaProvider: AgentIOSWebMediaToolProviding,
    nowMillis: @escaping () -> Int64
  ) -> AgentIOSWebIntelligenceToolProviding {
    guard provider is AgentIOSUnavailableWebIntelligenceToolProvider else {
      return provider
    }
    return defaultCatalogWebIntelligenceProvider(
      webMediaProvider: webMediaProvider,
      nowMillis: nowMillis
    )
  }

  private static func defaultCatalogWebIntelligenceProvider(
    webMediaProvider: AgentIOSWebMediaToolProviding,
    nowMillis: @escaping () -> Int64
  ) -> AgentIOSWebIntelligenceToolProviding {
    AgentIOSURLSessionWebIntelligenceProvider(
      webMediaProvider: webMediaProvider,
      nowMillis: nowMillis
    )
  }

  static func defaultOnDeviceRuntimeProvider(
    _ provider: AgentIOSOnDeviceRuntimeToolProviding,
    runtimeRootURL: URL? = nil,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64
  ) -> AgentIOSOnDeviceRuntimeToolProviding {
    guard provider is AgentIOSUnavailableOnDeviceRuntimeToolProvider else {
      return provider
    }
    return AgentIOSDefaultOnDeviceRuntimeProvider(
      runtimeRootURL: runtimeRootURL ?? AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
      fileManager: fileManager,
      nowMillis: nowMillis
    )
  }

  static func defaultSelfEvolutionProvider(
    _ provider: AgentIOSSelfEvolutionToolProviding,
    storeFileURL: URL? = nil,
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64
  ) -> AgentIOSSelfEvolutionToolProviding {
    guard provider is AgentIOSUnavailableSelfEvolutionToolProvider else {
      return provider
    }
    return AgentIOSDefaultSelfEvolutionProvider(
      store: AgentIOSFileSelfEvolutionTaskStore(
        fileURL: storeFileURL ?? AgentIOSFileSelfEvolutionTaskStore.defaultFileURL(),
        fileManager: fileManager
      ),
      runtimeProvider: runtimeProvider,
      nowMillis: nowMillis
    )
  }

  static func defaultMcpProvider(
    _ provider: AgentIOSMcpNativeToolProviding,
    packageRootURL: URL? = nil,
    auditStore: AgentMcpAuditStore = InMemoryAgentMcpAuditStore(),
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64
  ) -> AgentIOSMcpNativeToolProviding {
    guard provider is AgentIOSUnavailableMcpNativeToolProvider else {
      return provider
    }
    let rootURL = packageRootURL ?? AgentIOSMcpClientNativeProvider.defaultPackageRootURL(fileManager: fileManager)
    return AgentIOSMcpClientNativeProvider(
      registry: AgentMcpRegistry(
        FileAgentMcpStore(rootURL: rootURL, fileManager: fileManager),
        nowMillis: nowMillis
      ),
      auditStore: auditStore,
      packageRootURL: rootURL,
      fileManager: fileManager,
      nowMillis: nowMillis
    )
  }

  private static func defaultNotificationProvider(
    _ provider: AgentIOSNotificationToolProviding
  ) -> AgentIOSNotificationToolProviding {
    guard provider is AgentIOSUnavailableNotificationToolProvider else {
      return provider
    }
    return AgentIOSOwnedNotificationToolProvider()
  }

  static func selfEvolutionExecutableDefinitions(
    provider: AgentIOSSelfEvolutionToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSSelfEvolutionNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func desktopRemoteExecutableDefinitions(
    provider: AgentIOSDesktopRemoteToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSDesktopRemoteNativeToolExecutor(provider: provider)
    return AgentIOSDesktopRemoteNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func mcpExecutableDefinitions(
    provider: AgentIOSMcpNativeToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSMcpNativeToolExecutor(provider: provider)
    return AgentMcpNativeTools.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func onDeviceRuntimeExecutableDefinitions(
    provider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSOnDeviceRuntimeNativeToolExecutor(
      provider: provider,
      workspaceManager: provider.runtimeWorkspaceManager
    )
    return AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func projectRepositoryReadExecutableDefinitions(
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSProjectRepositoryReadToolExecutor(runtimeProvider: runtimeProvider)
    return AgentIOSProjectRepositoryReadToolCatalog
      .definitions(runtimeProvider: runtimeProvider)
      .map(executor.executableDefinition)
  }

  static func projectRepositoryMutationExecutableDefinitions(
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSProjectRepositoryMutationToolExecutor(runtimeProvider: runtimeProvider)
    return AgentIOSProjectRepositoryMutationToolCatalog
      .definitions(runtimeProvider: runtimeProvider)
      .map(executor.executableDefinition)
  }

  static func actionExecutableDefinitions(
    delegate: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses()
  ) -> [AgentNativeToolExecutableDefinition] {
    actionExecutableDefinitions(
      delegate: delegate,
      screenProvider: screenProvider,
      capabilityStatusProvider: { capabilityStatuses }
    )
  }

  static func actionExecutableDefinitions(
    delegate: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus],
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) -> [AgentNativeToolExecutableDefinition] {
    zip(
      supportedActionKinds,
      actionDefinitions(capabilityStatusProvider: capabilityStatusProvider, nowMillis: nowMillis)
    ).map { kind, definition in
      AgentActionNativeToolExecutor.executableDefinition(
        definition: definition,
        delegate: delegate,
        kind: kind,
        screenProvider: screenProvider
      )
    }
  }

  static func capabilities(for kind: AgentActionKind) -> Set<AgentPhoneCapabilityId> {
    switch kind {
    case .readScreen:
      return [.accessibilityUITree]
    case .copyScreenText:
      return [.accessibilityUITree, .clipboard]
    case .tap:
      return [.ownedAgentControls]
    case .pasteText:
      return [.ownedAgentInput, .clipboard]
    case .typeText, .deleteText:
      return [.ownedAgentInput]
    case .swipe:
      return [.ownedAgentTranscript]
    case .longPress:
      return [.ownedAgentLongPress]
    case .back:
      return [.ownedAgentNavigation]
    case .home, .recents, .lockScreen:
      return [.accessibilityGestures]
    case .openApp, .openURL, .setAlarm:
      return [.intentLaunch]
    case .replyNotification:
      return [.notificationReply]
    case .saveScreenKnowledge, .draftPlan, .createNotification, .importWebKnowledge, .callConnector, .callNativeTool, .controlDevice:
      return []
    }
  }

  private static func workspaceDefinitions() -> [AgentPhoneNativeToolDefinition] {
    [
      workspaceDefinition(workspaceInitialize, "Initialize app-private workspace", .low, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceMkdir, "Create workspace directory", .low, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceList, "List workspace directory", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceStat, "Inspect workspace entry", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceReadText, "Read workspace text file", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceReadBytes, "Read workspace binary file", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceWriteText, "Write workspace text file", .medium, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceWriteTextBatch, "Write a complete text project batch", .medium, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceCreateText, "Create workspace text file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceAppendText, "Append workspace text file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceWriteBytes, "Write workspace binary file", .medium, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceCreateBytes, "Create workspace binary file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceAppendBytes, "Append workspace binary file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceMove, "Move workspace entry", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceCopy, "Copy workspace entry", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceDelete, "Delete workspace entry", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceSearchText, "Search workspace text", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceApplyExactPatch, "Apply exact workspace patch", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceDiffSummary, "Summarize workspace diff", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceSha256, "Hash workspace file", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceZipCreate, "Create workspace zip", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceZipList, "List workspace zip", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceZipExtract, "Extract workspace zip", .medium, workspaceWriteConsent, .idempotencyKeyRequired)
    ]
  }

  private static func workspaceDefinition(
    _ id: String,
    _ title: String,
    _ risk: AgentNativeToolRisk,
    _ consentId: String,
    _ idempotency: AgentNativeToolIdempotency
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: version,
      title: title,
      description: "Bounded operation inside GalaxySSI app-private Agent workspace storage.",
      location: .application,
      inputSchema: workspaceInputSchema(id),
      outputSchema: workspaceOutputSchema(id),
      risk: risk,
      capabilities: ["workspace.app_private", "workspace.file.bounded"],
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: workspacePrivatePermission,
          title: "App-private workspace scope",
          description: "Restricts access to GalaxySSI-owned workspace storage."
        )
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: consentId,
          title: consentId == workspaceReadConsent ? "Read app-private workspace" : "Modify app-private workspace",
          description: "Authorizes this invocation to access the selected Agent workspace."
        )
      ],
      timeoutMillis: 15_000,
      idempotency: idempotency,
      availability: .available
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: fileExecutorId,
      provenanceMetadata: [
        "storage_scope": "app_private",
        "path_policy": "workspace_relative_no_symlinks",
        "result_policy": "bounded-v1"
      ]
    )
  }

  private static func actionDefinitions(
    capabilityStatuses: [AgentPhoneCapabilityStatus]
  ) -> [AgentPhoneNativeToolDefinition] {
    actionDefinitions(capabilityStatusProvider: { capabilityStatuses })
  }

  private static func actionDefinitions(
    capabilityStatusProvider: @escaping () -> [AgentPhoneCapabilityStatus],
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) -> [AgentPhoneNativeToolDefinition] {
    let snapshotProvider = AgentPhoneCapabilityStatusSnapshotProvider(
      source: capabilityStatusProvider,
      nowMillis: nowMillis
    )
    let initialStatuses = snapshotProvider.current()
    return supportedActionKinds.map { kind in
      let capabilityIds = capabilities(for: kind)
      let boundaries = capabilityIds.map { AgentPhoneCapabilityCatalog.find($0) }
      let descriptor = try! AgentNativeToolDescriptor(
        id: AgentNativeToolAgentActionAdapter.defaultToolId(kind),
        version: version,
        title: actionTitle(kind),
        description: actionDescription(kind),
        location: nativeLocation(boundaries),
        inputSchema: actionInputSchema(kind),
        outputSchema: actionOutputSchema(),
        risk: nativeRisk(boundaries.map(\.risk).max { $0.weight < $1.weight }),
        capabilities: Set(capabilityIds.map(\.wireId)),
        requiredPermissions: permissionRequirements(boundaries),
        requiredConsents: consentRequirements(boundaries),
        timeoutMillis: 15_000,
        idempotency: .nonIdempotent,
        availability: capabilityAvailability(capabilityIds, statuses: initialStatuses)
      )
      return AgentPhoneNativeToolDefinition(
        descriptor: descriptor,
        executorId: actionExecutorId,
        provenanceMetadata: [
          "adapter": "AgentActionExecutor",
          "legacy_action_kind": kind.rawValue,
          "result_policy": "bounded-v1",
          "platform": "ios"
        ],
        availabilityProvider: AgentNativeToolAvailabilityProvider { _ in
          capabilityAvailability(capabilityIds, statuses: snapshotProvider.current())
        }
      )
    }
  }

  private static func permissionRequirements(
    _ boundaries: [AgentPhoneCapabilityBoundary]
  ) -> [AgentNativePermissionRequirement] {
    var requirements: [String: AgentNativePermissionRequirement] = [:]
    for boundary in boundaries {
      for permission in boundary.platformPermissions.sorted() {
        requirements[permission] = AgentNativePermissionRequirement(
          id: permission,
          title: permission,
          description: "iOS permission or Info.plist usage key required by \(boundary.id.wireId)."
        )
      }
      for access in boundary.specialAccess.sorted(by: { $0.rawValue < $1.rawValue }) {
        let id = "galaxyssi.special_access.\(access.rawValue.lowercased())"
        requirements[id] = AgentNativePermissionRequirement(
          id: id,
          title: access.rawValue.replacingOccurrences(of: "_", with: " ").lowercased(),
          description: "Special platform access required by \(boundary.id.wireId)."
        )
      }
    }
    if requirements.isEmpty {
      requirements[normalAppExecutionPermission] = AgentNativePermissionRequirement(
        id: normalAppExecutionPermission,
        title: "Normal app execution",
        description: "No runtime permission or special-access grant is required.",
        required: false
      )
    }
    return requirements.values.sorted { $0.id < $1.id }
  }

  private static func consentRequirements(
    _ boundaries: [AgentPhoneCapabilityBoundary]
  ) -> [AgentNativeConsentRequirement] {
    let consents = boundaries.reduce(into: Set<AgentPhoneUserConsent>()) { result, boundary in
      result.formUnion(boundary.userConsent)
    }
    if consents.isEmpty || consents == Set([.none]) {
      return [
        AgentNativeConsentRequirement(
          id: "galaxyssi.consent.none",
          title: "No additional consent",
          description: "This capability has no additional interactive consent requirement.",
          required: false
        )
      ]
    }
    return consents
      .filter { $0 != .none }
      .sorted { $0.rawValue < $1.rawValue }
      .map { consent in
        AgentNativeConsentRequirement(
          id: "galaxyssi.consent.\(consent.rawValue.lowercased())",
          title: consent.rawValue.replacingOccurrences(of: "_", with: " ").lowercased(),
          description: "User consent required by the phone capability boundary."
        )
      }
  }

  private static func capabilityAvailability(
    _ ids: Set<AgentPhoneCapabilityId>,
    statuses: [AgentPhoneCapabilityStatus]
  ) -> AgentNativeToolAvailability {
    guard !ids.isEmpty else {
      return AgentNativeToolAvailability(status: .unavailable, reason: "No phone capability mapping is declared")
    }
    let byId = Dictionary(uniqueKeysWithValues: statuses.map { ($0.boundary.id, $0) })
    let resolved = ids.map { id in
      byId[id] ?? AgentPhoneCapabilityStatus(
        boundary: AgentPhoneCapabilityCatalog.find(id),
        availability: .unknown,
        evidence: "Capability status was not provided"
      )
    }
    if let unavailable = resolved.first(where: { $0.availability.nativeAvailabilityStatus == .unavailable }) {
      return AgentNativeToolAvailability(
        status: .unavailable,
        reason: unavailable.evidence.isEmpty ? unavailable.boundary.limitation : unavailable.evidence
      )
    }
    if let setup = resolved.first(where: { $0.availability.nativeAvailabilityStatus == .requiresSetup }) {
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: setup.evidence.isEmpty ? setup.boundary.limitation : setup.evidence
      )
    }
    let limitedReason = resolved
      .filter { $0.availability == .limited }
      .map(\.boundary.limitation)
      .joined(separator: "; ")
    return AgentNativeToolAvailability(status: .available, reason: String(limitedReason.prefix(maxReasonCharacters)))
  }

  private static func nativeLocation(_ boundaries: [AgentPhoneCapabilityBoundary]) -> AgentNativeToolLocation {
    if boundaries.contains(where: { $0.executionLocation == .accessibilityService }) {
      return .accessibilityService
    }
    if boundaries.contains(where: {
      $0.executionLocation == .androidSystemService ||
        $0.executionLocation == .systemUIHandoff ||
        $0.executionLocation == .notificationListenerService ||
        $0.executionLocation == .screenCaptureService
    }) {
      return .androidSystem
    }
    if boundaries.allSatisfy({ $0.executionLocation == .appProcess }) {
      return .application
    }
    return .phone
  }

  private static func nativeRisk(_ risk: AgentRisk?) -> AgentNativeToolRisk {
    switch risk ?? .medium {
    case .low: return .low
    case .medium: return .medium
    case .high: return .high
    case .blocked: return .blocked
    }
  }

  private static func actionTitle(_ kind: AgentActionKind) -> String {
    kind.rawValue.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
  }

  private static func actionDescription(_ kind: AgentActionKind) -> String {
    switch kind {
    case .readScreen:
      return "Reads bounded screen context through the iOS phone action adapter when the capability boundary allows it."
    case .tap, .typeText, .swipe, .longPress, .deleteText, .pasteText, .copyScreenText, .back, .home, .recents, .lockScreen:
      return "Adapts a legacy phone action into a native tool descriptor with iOS capability, consent, and risk metadata."
    case .openApp, .openURL, .setAlarm:
      return "Hands work to an app or system UI surface while keeping target completion untrusted."
    case .replyNotification:
      return "Replies only through GalaxySSI-owned notification actions and explicit user confirmation."
    case .saveScreenKnowledge, .draftPlan, .createNotification, .importWebKnowledge, .callConnector, .callNativeTool, .controlDevice:
      return "Unsupported phone-native action kind for this catalog."
    }
  }

  private static func workspaceInputSchema(_ id: String) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONValue] = [
      "workspace_id": .object(stringSchema(minLength: 1, maxLength: 64))
    ]
    var required: [String] = ["workspace_id"]
    if id == workspaceInitialize {
      return objectSchema(properties: properties, required: required)
    }
    if id == workspaceList {
      properties["path"] = .object(stringSchema(maxLength: 1_024))
      properties["recursive"] = .object(boolSchema())
      properties["max_entries"] = .object(integerSchema(minimum: 1))
      return objectSchema(properties: properties, required: required)
    }
    if [workspaceMove, workspaceCopy].contains(id) {
      properties["source_path"] = .object(stringSchema(maxLength: 1_024))
      properties["destination_path"] = .object(stringSchema(maxLength: 1_024))
      properties["overwrite"] = .object(boolSchema())
      properties["create_parents"] = .object(boolSchema())
      return objectSchema(properties: properties, required: ["workspace_id", "source_path", "destination_path"])
    }
    if id == workspaceZipCreate {
      properties["archive_path"] = .object(stringSchema(maxLength: 1_024))
      properties["source_paths"] = .object(arraySchema(items: stringSchema(maxLength: 1_024), minItems: 1, maxItems: 2_048))
      properties["overwrite"] = .object(boolSchema())
      properties["create_parents"] = .object(boolSchema())
      return objectSchema(properties: properties, required: ["workspace_id", "archive_path", "source_paths"])
    }
    if id == workspaceZipList {
      properties["archive_path"] = .object(stringSchema(maxLength: 1_024))
      return objectSchema(properties: properties, required: ["workspace_id", "archive_path"])
    }
    if id == workspaceZipExtract {
      properties["archive_path"] = .object(stringSchema(maxLength: 1_024))
      properties["destination_path"] = .object(stringSchema(maxLength: 1_024))
      properties["overwrite"] = .object(boolSchema())
      return objectSchema(properties: properties, required: ["workspace_id", "archive_path", "destination_path"])
    }
    if id == workspaceWriteTextBatch {
      properties["files"] = .object(arraySchema(
        items: objectSchema(properties: [
          "path": .object(stringSchema(minLength: 1, maxLength: 1_024)),
          "text": .object(stringSchema(maxLength: 1_048_576))
        ], required: ["path", "text"]),
        minItems: 1,
        maxItems: 64
      ))
      properties["overwrite"] = .object(boolSchema())
      return objectSchema(properties: properties, required: ["workspace_id", "files"])
    }
    if id != workspaceInitialize {
      properties["path"] = .object(stringSchema(maxLength: 1_024))
      required.append("path")
    }
    if [workspaceMkdir, workspaceDelete].contains(id) {
      properties["recursive"] = .object(boolSchema())
    }
    if [workspaceReadText, workspaceReadBytes].contains(id) {
      properties["max_bytes"] = .object(integerSchema(minimum: 1))
    }
    if [workspaceWriteText, workspaceCreateText, workspaceAppendText].contains(id) {
      properties["text"] = .object(stringSchema(maxLength: 1_048_576))
      required.append("text")
    }
    if [workspaceWriteText, workspaceCreateText].contains(id) {
      properties["create_parents"] = .object(boolSchema())
    }
    if [workspaceWriteBytes, workspaceCreateBytes, workspaceAppendBytes].contains(id) {
      properties["base64"] = .object(stringSchema(maxLength: 22_369_624))
      required.append("base64")
    }
    if [workspaceWriteBytes, workspaceCreateBytes].contains(id) {
      properties["create_parents"] = .object(boolSchema())
    }
    if id == workspaceSearchText {
      properties["query"] = .object(stringSchema(minLength: 1, maxLength: 4_096))
      properties["case_sensitive"] = .object(boolSchema())
      properties["max_results"] = .object(integerSchema(minimum: 1))
      required.append("query")
    }
    if id == workspaceApplyExactPatch {
      properties["expected_text"] = .object(stringSchema(minLength: 1, maxLength: 1_048_576))
      properties["replacement_text"] = .object(stringSchema(maxLength: 1_048_576))
      properties["expected_occurrences"] = .object(integerSchema(minimum: 1))
      required.append(contentsOf: ["expected_text", "replacement_text"])
    }
    if id == workspaceDiffSummary {
      properties["proposed_text"] = .object(stringSchema(maxLength: 1_048_576))
      required.append("proposed_text")
    }
    return objectSchema(properties: properties, required: required)
  }

  private static func workspaceOutputSchema(_ id: String) -> AgentMcpJSONObject {
    if id == workspaceList {
      return directoryListingSchema()
    }
    if id == workspaceStat {
      return workspaceMetadataSchema()
    }
    if id == workspaceReadText {
      return textReadSchema()
    }
    if id == workspaceReadBytes {
      return bytesReadSchema()
    }
    if id == workspaceSearchText {
      return searchResultSchema()
    }
    if id == workspaceApplyExactPatch {
      return patchResultSchema()
    }
    if id == workspaceDiffSummary {
      return diffSummarySchema()
    }
    if id == workspaceSha256 {
      return digestSchema()
    }
    if [workspaceZipCreate, workspaceZipList].contains(id) {
      return zipListingSchema()
    }
    if id == workspaceZipExtract {
      return zipExtractionSchema()
    }
    if id == workspaceWriteTextBatch {
      return batchMutationSchema()
    }
    return mutationSchema()
  }

  private static func workspaceMetadataSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "type": .object(enumStringSchema(["file", "directory"])),
      "size_bytes": .object(integerSchema(minimum: 0)),
      "last_modified_epoch_ms": .object(integerSchema(minimum: 0))
    ], required: ["path", "type", "size_bytes", "last_modified_epoch_ms"])
  }

  private static func mutationSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "kind": .object(stringSchema(maxLength: 64)),
      "path": .object(stringSchema(maxLength: 4_096)),
      "source_path": .object(stringSchema(maxLength: 4_096)),
      "affected_entries": .object(integerSchema(minimum: 0)),
      "affected_bytes": .object(integerSchema(minimum: 0)),
      "metadata": .object(workspaceMetadataSchema())
    ], required: ["kind", "path", "source_path", "affected_entries", "affected_bytes"])
  }

  private static func batchMutationSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "files": .object(arraySchema(items: mutationSchema(), minItems: 1, maxItems: 64)),
      "affected_entries": .object(integerSchema(minimum: 1)),
      "affected_bytes": .object(integerSchema(minimum: 0))
    ], required: ["files", "affected_entries", "affected_bytes"])
  }

  private static func directoryListingSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "recursive": .object(boolSchema()),
      "entries": .object(arraySchema(items: workspaceMetadataSchema(), maxItems: 10_000))
    ], required: ["path", "recursive", "entries"])
  }

  private static func textReadSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "text": .object(stringSchema(maxLength: 1_048_576)),
      "size_bytes": .object(integerSchema(minimum: 0)),
      "sha256": .object(stringSchema(minLength: 64, maxLength: 64))
    ], required: ["path", "text", "size_bytes", "sha256"])
  }

  private static func bytesReadSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "base64": .object(stringSchema(maxLength: 11_184_812)),
      "metadata": .object(workspaceMetadataSchema()),
      "sha256": .object(stringSchema(minLength: 64, maxLength: 64))
    ], required: ["path", "base64", "metadata", "sha256"])
  }

  private static func searchResultSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "query": .object(stringSchema(maxLength: 4_096)),
      "matches": .object(arraySchema(items: objectSchema(properties: [
        "path": .object(stringSchema(maxLength: 4_096)),
        "line": .object(integerSchema(minimum: 1)),
        "column": .object(integerSchema(minimum: 1)),
        "excerpt": .object(stringSchema(maxLength: 512))
      ], required: ["path", "line", "column", "excerpt"]), maxItems: 500)),
      "scanned_files": .object(integerSchema(minimum: 0)),
      "skipped_files": .object(integerSchema(minimum: 0)),
      "scanned_bytes": .object(integerSchema(minimum: 0)),
      "truncated": .object(boolSchema())
    ], required: ["query", "matches", "scanned_files", "skipped_files", "scanned_bytes", "truncated"])
  }

  private static func diffSummarySchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "before_sha256": .object(stringSchema(minLength: 64, maxLength: 64)),
      "after_sha256": .object(stringSchema(minLength: 64, maxLength: 64)),
      "before_bytes": .object(integerSchema(minimum: 0)),
      "after_bytes": .object(integerSchema(minimum: 0)),
      "before_lines": .object(integerSchema(minimum: 0)),
      "after_lines": .object(integerSchema(minimum: 0)),
      "added_lines": .object(integerSchema(minimum: 0)),
      "deleted_lines": .object(integerSchema(minimum: 0)),
      "changed_line_pairs": .object(integerSchema(minimum: 0)),
      "first_changed_line": .object(integerSchema(minimum: 1))
    ], required: [
      "before_sha256", "after_sha256", "before_bytes", "after_bytes",
      "before_lines", "after_lines", "added_lines", "deleted_lines", "changed_line_pairs"
    ])
  }

  private static func patchResultSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "replacements": .object(integerSchema(minimum: 1)),
      "diff": .object(diffSummarySchema()),
      "metadata": .object(workspaceMetadataSchema())
    ], required: ["path", "replacements", "diff", "metadata"])
  }

  private static func digestSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "algorithm": .object(enumStringSchema(["SHA-256"])),
      "hex": .object(stringSchema(minLength: 64, maxLength: 64)),
      "size_bytes": .object(integerSchema(minimum: 0))
    ], required: ["path", "algorithm", "hex", "size_bytes"])
  }

  private static func zipListingSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "archive_path": .object(stringSchema(maxLength: 4_096)),
      "archive_bytes": .object(integerSchema(minimum: 0)),
      "total_compressed_bytes": .object(integerSchema(minimum: 0)),
      "total_uncompressed_bytes": .object(integerSchema(minimum: 0)),
      "entries": .object(arraySchema(items: zipEntrySchema(), maxItems: 2_048))
    ], required: [
      "archive_path",
      "archive_bytes",
      "total_compressed_bytes",
      "total_uncompressed_bytes",
      "entries"
    ])
  }

  private static func zipExtractionSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "archive_path": .object(stringSchema(maxLength: 4_096)),
      "destination_path": .object(stringSchema(maxLength: 4_096)),
      "extracted_entries": .object(integerSchema(minimum: 0)),
      "extracted_bytes": .object(integerSchema(minimum: 0))
    ], required: ["archive_path", "destination_path", "extracted_entries", "extracted_bytes"])
  }

  private static func zipEntrySchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 512)),
      "directory": .object(boolSchema()),
      "compressed_bytes": .object(integerSchema(minimum: 0)),
      "uncompressed_bytes": .object(integerSchema(minimum: 0)),
      "compression_ratio": .object(numberSchema(minimum: 0)),
      "crc32": .object(integerSchema(minimum: 0)),
      "last_modified_epoch_ms": .object(integerSchema(minimum: 0))
    ], required: [
      "path",
      "directory",
      "compressed_bytes",
      "uncompressed_bytes",
      "compression_ratio",
      "crc32",
      "last_modified_epoch_ms"
    ])
  }

  private static func actionInputSchema(_ kind: AgentActionKind) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONValue] = [
      "target": .object(stringSchema(maxLength: 512)),
      "parameters": .object(objectSchema(additionalProperties: true))
    ]
    var required: [String] = ["target"]
    if kind == .openURL {
      properties["url"] = .object(stringSchema(minLength: 1, maxLength: 2_048))
      required.append("url")
    }
    if kind == .replyNotification {
      properties["notification_key"] = .object(stringSchema(minLength: 1, maxLength: 1_024))
      properties["reply_text"] = .object(stringSchema(minLength: 1, maxLength: 16_384))
      required.append(contentsOf: ["notification_key", "reply_text"])
    }
    return objectSchema(properties: properties, required: required)
  }

  private static func actionOutputSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "action_id": .object(stringSchema(maxLength: 128)),
      "success": .object(["type": .string("boolean")]),
      "message": .object(stringSchema(maxLength: 2_048)),
      "metadata": .object(objectSchema(additionalProperties: true))
    ], required: ["action_id", "success", "message", "metadata"])
  }

  private static func objectSchema(
    properties: [String: AgentMcpJSONValue] = [:],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(
    minLength: Int64? = nil,
    maxLength: Int64? = nil
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("string")]
    if let minLength { schema["minLength"] = .int(minLength) }
    if let maxLength { schema["maxLength"] = .int(maxLength) }
    return schema
  }

  private static func integerSchema(minimum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("integer")]
    if let minimum { schema["minimum"] = .int(minimum) }
    return schema
  }

  private static func numberSchema(minimum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("number")]
    if let minimum { schema["minimum"] = .int(minimum) }
    return schema
  }

  private static func boolSchema() -> AgentMcpJSONObject {
    ["type": .string("boolean")]
  }

  private static func enumStringSchema(_ values: [String]) -> AgentMcpJSONObject {
    var schema = stringSchema()
    schema["enum"] = .array(values.map(AgentMcpJSONValue.string))
    return schema
  }

  private static func arraySchema(
    items: AgentMcpJSONObject,
    minItems: Int64? = nil,
    maxItems: Int64? = nil
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("array"),
      "items": .object(items)
    ]
    if let minItems { schema["minItems"] = .int(minItems) }
    if let maxItems { schema["maxItems"] = .int(maxItems) }
    return schema
  }

  private static let maxReasonCharacters = 2_048
  private static let normalAppExecutionPermission = "galaxyssi.scope.normal_app_execution"
  private static let workspaceToolIds = [
    workspaceInitialize,
    workspaceMkdir,
    workspaceList,
    workspaceStat,
    workspaceReadText,
    workspaceReadBytes,
    workspaceWriteText,
    workspaceWriteTextBatch,
    workspaceCreateText,
    workspaceAppendText,
    workspaceWriteBytes,
    workspaceCreateBytes,
    workspaceAppendBytes,
    workspaceMove,
    workspaceCopy,
    workspaceDelete,
    workspaceSearchText,
    workspaceApplyExactPatch,
    workspaceDiffSummary,
    workspaceSha256,
    workspaceZipCreate,
    workspaceZipList,
    workspaceZipExtract
  ]
}
