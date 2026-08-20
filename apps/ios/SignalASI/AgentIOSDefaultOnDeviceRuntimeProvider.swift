import Foundation

struct AgentIOSDefaultOnDeviceRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding {
  var implementationId: String = "signalasi.ios.default_runtime_status"

  private let runtimeRootURL: URL
  private let workspaceManager: AgentRuntimeProjectWorkspaceManager
  private let fileManager: FileManager
  private let nowMillis: () -> Int64
  private let catalogManager: AgentIOSRuntimePackCatalogManager
  private let signatureVerifier: (AgentRuntimePackManifest) -> Bool
  private let broker: AgentIOSRuntimeBrokerProviding
  private let lifecycleStore: AgentIOSRuntimeBrokerLifecycleStore

  var runtimeWorkspaceManager: AgentRuntimeProjectWorkspaceManager? {
    workspaceManager
  }

  init(
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    workspaceManager: AgentRuntimeProjectWorkspaceManager? = nil,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    broker: AgentIOSRuntimeBrokerProviding? = nil,
    lifecycleStore: AgentIOSRuntimeBrokerLifecycleStore = AgentIOSRuntimeBrokerLifecycleStore(),
    signatureVerifier: @escaping (AgentRuntimePackManifest) -> Bool = { manifest in
      AgentIOSRuntimePackTrust.verify(manifest: manifest)
    }
  ) {
    self.runtimeRootURL = runtimeRootURL
    self.fileManager = fileManager
    self.nowMillis = nowMillis
    self.signatureVerifier = signatureVerifier
    self.workspaceManager = workspaceManager ?? AgentRuntimeProjectWorkspaceManager(
      runtimeRoot: runtimeRootURL.appendingPathComponent("runs", isDirectory: true),
      projectRoot: runtimeRootURL.appendingPathComponent("projects", isDirectory: true),
      nowMillis: nowMillis
    )
    self.catalogManager = AgentIOSRuntimePackCatalogManager(
      runtimeRootURL: runtimeRootURL,
      nowMillis: nowMillis
    )
    self.broker = broker ?? AgentIOSRuntimeBrokerClient(nowMillis: nowMillis)
    self.lifecycleStore = lifecycleStore
  }

  static func defaultRuntimeRootURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL.appendingPathComponent("on-device-runtime", isDirectory: true)
  }

  func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
    switch operation {
    case .status, .workspaceStatus, .workspaceRollback, .listPacks,
         .softwareCatalog, .softwareSearch, .softwareInspect:
      return .available
    case .installPack, .softwareInstall:
      return .available
    case .softwareRemove:
      return availability(operation: .execute)
    case .execute:
      return broker.availability()
    }
  }

  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    switch operation {
    case .status:
      return inspectBroker(invocation)
    case .workspaceStatus:
      return workspaceStatus(invocation)
    case .workspaceRollback:
      return rollback(input: input, invocation: invocation)
    case .listPacks:
      return AgentNativeToolExecutionResult.success(
        output: [
          "packs": .array(packStatuses().map { .object(packOutput($0)) }),
          "observed_at_epoch_ms": .int(max(0, nowMillis()))
        ],
        message: "iOS on-device runtime packs listed",
        metadata: baseMetadata()
      )
    case .installPack:
      return installPack(input: input, invocation: invocation)
    case .softwareCatalog:
      if let result = brokerSoftware(operation: operation, input: input, invocation: invocation) { return result }
      return AgentNativeToolExecutionResult.success(
        output: softwareCatalogOutput(),
        message: "Compatible iOS runtime software listed",
        metadata: baseMetadata(["operation": .string("software_catalog")])
      )
    case .softwareSearch:
      if softwareSource(input) == AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage,
         let result = brokerSoftware(operation: operation, input: input, invocation: invocation) { return result }
      return searchSoftware(input: input)
    case .softwareInspect:
      if softwareSource(input, softwareId: softwareId(input)) == AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage,
         let result = brokerSoftware(operation: operation, input: input, invocation: invocation) { return result }
      return inspectSoftware(input: input)
    case .softwareInstall:
      if softwareSource(input, softwareId: softwareId(input)) == AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage,
         let result = brokerSoftware(operation: operation, input: input, invocation: invocation) { return result }
      return installSoftware(input: input, invocation: invocation)
    case .softwareRemove:
      guard softwareSource(input, softwareId: softwareId(input)) == AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage else {
        return unavailableLinuxPackageManagement()
      }
      return brokerSoftware(operation: operation, input: input, invocation: invocation) ?? unavailableLinuxPackageManagement()
    case .execute:
      return executeWithBroker(input: input, invocation: invocation)
    }
  }

  private func brokerSoftware(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult? {
    guard availability(operation: .execute).status == .available else { return nil }
    do {
      let output = try broker.invoke(
        operation: operation,
        input: input,
        context: invocation.context,
        deadlineEpochMillis: invocation.deadlineEpochMillis
      )
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: output["message"]?.stringValue?.nonEmpty ?? "iOS Linux software operation completed",
        metadata: baseMetadata(["broker": .string(broker.implementationId)])
      )
    } catch let error as AgentIOSRuntimeBrokerError {
      return AgentNativeToolExecutionResult.failure(
        code: error.code,
        message: error.localizedDescription,
        retryable: error.retryable,
        details: baseMetadata(["broker": .string(broker.implementationId)])
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "runtime_broker_software_failed",
        message: error.localizedDescription.ifBlank("The local iOS runtime broker failed"),
        retryable: true,
        details: baseMetadata(["broker": .string(broker.implementationId)])
      )
    }
  }

  private func statusOutput() -> AgentMcpJSONObject {
    let packs = packStatuses()
    let reason = runtimeSetupReason()
    let brokerConfigured = availability(operation: .execute).status == .available
    return [
      "backend": .string(brokerConfigured ? "ios_runtime_broker" : "none"),
      "backend_ready": .bool(false),
      "reason": .string(reason),
      "architecture": .string(hostArchitecture()),
      "avf_advertised": .bool(false),
      "lifecycle": .object(lifecycleOutput()),
      "linux_system": .object(linuxSystemOutput()),
      "packs": .array(packs.map { .object(packOutput($0)) }),
      "languages": .array(AgentRuntimeLanguage.allCases.map {
        .object(languageOutput($0, packs: packs, backendReady: false))
      }),
      "observed_at_epoch_ms": .int(max(0, nowMillis())),
      "runtime_store": .string("app_private_application_support"),
      "execution_target": .string("ios"),
      "linux_base_recovery_baseline": .string(AgentRuntimePackCatalogPolicy.linuxBaseRecoveryVersion),
      "linux_base_recovery_required": .bool(false)
    ]
  }

  private func lifecycleOutput() -> AgentMcpJSONObject {
    let state = lifecycleStore.snapshot()
    return [
      "phase": .string(state.phase),
      "reason": .string(state.reason),
      "consecutive_failures": .int(Int64(state.consecutiveFailures)),
      "last_transition_at_millis": .int(state.lastTransitionAtMillis),
      "last_ready_at_millis": .int(state.lastReadyAtMillis),
      "next_attempt_at_millis": .int(state.nextAttemptAtMillis)
    ]
  }

  private func linuxSystemOutput() -> AgentMcpJSONObject {
    return [
      "distribution": .string("paired jailbreak Linux runtime"),
      "execution_principal": .string("configured_jailbreak_linux_prefix"),
      "persistent": .bool(true),
      "package_managers": .array([]),
      "package_manager_ready": .bool(false),
      "base_version": .string(""),
      "package_management": .string("runtime_broker_managed")
    ]
  }

  private func installPack(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let packId = (input["pack_id"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard AgentRuntimePackCatalogPolicy.requiredPacks.contains(packId) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_runtime_pack",
        message: "Runtime pack is invalid"
      )
    }
    do {
      try invocation.reportProgress(
        stage: "catalog",
        message: "Refreshing the trusted runtime catalog",
        percent: 10
      )
      let installed = try catalogManager.install(
        packId: packId,
        checkpoint: { try invocation.checkpoint() },
        onDownloadProgress: { progress in
          let percent = progress.totalBytes > 0
            ? min(100, max(0, Int(progress.downloadedBytes * 100 / progress.totalBytes)))
            : nil
          try? invocation.reportProgress(
            stage: "download",
            message: "Downloading \(packId)",
            percent: percent
          )
        },
        onInstallProgress: { progress in
          try? invocation.reportProgress(
            stage: "install",
            message: "Installing \(packId): \(progress.stage.rawValue.lowercased())"
          )
        }
      )
      return AgentNativeToolExecutionResult.success(
        output: [
          "requested_pack": .string(packId),
          "installed": .array(installed.map { result in
            .object([
              "pack_id": .string(result.packId),
              "version": .string(result.version),
              "state": .string(result.state.rawValue),
              "installed_bytes": .int(result.installedBytes),
              "reason": .string(result.reason)
            ])
          })
        ],
        message: "Trusted runtime pack is ready",
        metadata: baseMetadata(["operation": .string("signed_catalog_download_install")])
      )
    } catch let error as AgentNativeToolInvocationError {
      return AgentNativeToolExecutionResult.failure(
        code: "runtime_pack_install_cancelled",
        message: error.localizedDescription,
        retryable: true
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "runtime_pack_install_failed",
        message: error.localizedDescription.ifBlank("Runtime pack installation failed")
      )
    }
  }

  private func softwareCatalogOutput() -> AgentMcpJSONObject {
    let packs = packStatuses()
    return [
      "architecture": .string(hostArchitecture()),
      "linux_ready": .bool(false),
      "sources": .array([
        .object([
          "id": .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack),
          "trusted": .bool(true),
          "searchable": .bool(true),
          "install_tool_id": .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstall)
        ]),
        .object([
          "id": .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage),
          "trusted": .bool(false),
          "searchable": .bool(false),
          "reason": .string("Unmanaged Linux package management is unavailable on iOS")
        ])
      ]),
      "software": .array(packs.map { .object(softwarePackOutput($0)) }),
      "observed_at_epoch_ms": .int(max(0, nowMillis()))
    ]
  }

  private func searchSoftware(input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    let query = (input["query"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !query.isEmpty else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_software_query",
        message: "Software search query is required"
      )
    }
    let source = requestedSoftwareSource(input)
    guard source != AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage else {
      return AgentNativeToolExecutionResult.success(
        output: [
          "query": .string(query),
          "results": .array([]),
          "source_errors": .array([
            .object([
              "source": .string(source),
              "message": .string("Unmanaged Linux package search is unavailable on iOS")
            ])
          ])
        ],
        message: "Compatible iOS runtime software searched",
        metadata: baseMetadata()
      )
    }
    let limit = max(1, min(
      Int(input["limit"]?.intValue ?? 10),
      Int(AgentIOSOnDeviceRuntimeNativeToolCatalog.maxSoftwareResults)
    ))
    let results = packStatuses()
      .filter { softwareMatches(query: query, pack: $0) }
      .prefix(limit)
      .map { AgentMcpJSONValue.object(softwarePackOutput($0)) }
    return AgentNativeToolExecutionResult.success(
      output: [
        "query": .string(query),
        "results": .array(Array(results)),
        "source_errors": .array([]),
        "observed_at_epoch_ms": .int(max(0, nowMillis()))
      ],
      message: "Compatible iOS runtime software searched",
      metadata: baseMetadata()
    )
  }

  private func inspectSoftware(input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    guard let softwareId = softwareId(input) else {
      return invalidRuntimeSoftware()
    }
    guard softwareSource(input, softwareId: softwareId) != AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage else {
      return unavailableLinuxPackageManagement()
    }
    guard let pack = packStatuses().first(where: { $0.id == softwareId }) else {
      return AgentNativeToolExecutionResult.failure(
        code: "software_not_found",
        message: "Managed runtime pack was not found"
      )
    }
    return AgentNativeToolExecutionResult.success(
      output: softwarePackOutput(pack),
      message: "Compatible iOS runtime software inspected",
      metadata: baseMetadata()
    )
  }

  private func installSoftware(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    guard let softwareId = softwareId(input) else {
      return invalidRuntimeSoftware()
    }
    guard softwareSource(input, softwareId: softwareId) != AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage else {
      return unavailableLinuxPackageManagement()
    }
    guard AgentRuntimePackCatalogPolicy.requiredPacks.contains(softwareId) else {
      return AgentNativeToolExecutionResult.failure(
        code: "software_not_found",
        message: "Managed runtime pack was not found"
      )
    }
    var packInput = input
    packInput["pack_id"] = .string(softwareId)
    let result = installPack(input: packInput, invocation: invocation)
    guard result.isSuccess else { return result }
    var output = result.output
    output["software_id"] = .string(softwareId)
    output["source"] = .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: "Compatible iOS runtime software installed and verified",
      metadata: result.metadata
    )
  }

  private func softwarePackOutput(_ pack: AgentRuntimePackStatus) -> AgentMcpJSONObject {
    [
      "software_id": .string(pack.id),
      "source": .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack),
      "version": .string(pack.manifest?.version ?? ""),
      "installed": .bool(pack.state == .ready),
      "compatible": .bool(pack.state != .incompatible),
      "state": .string(pack.state.rawValue),
      "reason": .string(pack.reason),
      "architecture": .string(pack.manifest?.architecture ?? hostArchitecture()),
      "capabilities": .array((pack.manifest?.capabilities ?? []).sorted().map(AgentMcpJSONValue.string)),
      "install_tool_id": .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstall)
    ]
  }

  private func softwareMatches(query: String, pack: AgentRuntimePackStatus) -> Bool {
    let terms = [pack.id] + softwareAliases[pack.id, default: []] + (pack.manifest?.capabilities ?? [])
    return terms.contains { $0.localizedCaseInsensitiveContains(query) }
  }

  private func softwareId(_ input: AgentMcpJSONObject) -> String? {
    let value = (input["software_id"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.range(
      of: "^[a-z0-9][a-z0-9+.-]{0,127}$",
      options: .regularExpression
    ) != nil else {
      return nil
    }
    return value
  }

  private func softwareSource(_ input: AgentMcpJSONObject, softwareId: String? = nil) -> String {
    let source = requestedSoftwareSource(input)
    switch source {
    case AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage:
      return source
    case AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack:
      return AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack
    case AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceAuto, "":
      let id = softwareId ?? self.softwareId(input)
      return AgentRuntimePackCatalogPolicy.requiredPacks.contains(id ?? "")
        ? AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack
        : AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage
    default:
      return AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack
    }
  }

  private func requestedSoftwareSource(_ input: AgentMcpJSONObject) -> String {
    let source = (input["source"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    switch source {
    case AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceRuntimePack,
         AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage:
      return source
    default:
      return AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceAuto
    }
  }

  private func invalidRuntimeSoftware() -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "software_not_found",
      message: "A supported runtime software id is required"
    )
  }

  private func unavailableLinuxPackageManagement() -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "ios_linux_package_management_unavailable",
      message: "iOS does not expose an unmanaged Linux package manager; use a signed runtime pack"
    )
  }

  private let softwareAliases: [String: [String]] = [
    "linux-base": ["linux", "shell", "debian", "git", "ssh", "curl", "wget", "zip"],
    "python-uv": ["python", "uv", "pip"],
    "node-js": ["node", "javascript", "typescript", "npm"],
    "go": ["golang"],
    "rust": ["cargo"],
    "cpp": ["c", "c++", "clang"],
    "java": ["jdk", "gradle"],
    "browser-automation": ["browser", "playwright", "web"],
    "ffmpeg": ["media", "ffprobe", "video", "audio"]
  ]

  private func workspaceStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    do {
      let status = try workspaceManager.workspaceStatus(workspaceId(invocation.context))
      return AgentNativeToolExecutionResult.success(
        output: status.publicValue().merging([
          "observed_at_epoch_ms": .int(max(0, nowMillis()))
        ]) { current, _ in current },
        message: "iOS on-device project workspace inspected",
        metadata: baseMetadata()
      )
    } catch {
      return workspaceFailure(
        code: "runtime_workspace_status_failed",
        message: error.localizedDescription.ifBlank("iOS runtime workspace status failed"),
        error: error
      )
    }
  }

  private func rollback(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let checkpointId = (input["checkpoint_id"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !checkpointId.isEmpty else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_runtime_checkpoint",
        message: "Runtime checkpoint id is required"
      )
    }
    do {
      let restored = try workspaceManager.rollback(
        workspaceId: workspaceId(invocation.context),
        checkpointId: checkpointId,
        byteLimit: maxRollbackBytes
      )
      return AgentNativeToolExecutionResult.success(
        output: [
          "checkpoint_id": .string(checkpointId),
          "workspace_id": .string(restored.workspaceId),
          "workspace_file_count": .int(Int64(restored.fileCount)),
          "workspace_bytes": .int(restored.totalBytes),
          "workspace_disposition": .string(AgentRuntimeProjectWorkspaceDisposition.rolledBack.rawValue),
          "observed_at_epoch_ms": .int(max(0, nowMillis()))
        ],
        message: "iOS on-device project checkpoint restored",
        metadata: baseMetadata([
          "operation": .string("atomic_checkpoint_restore")
        ])
      )
    } catch {
      return workspaceFailure(
        code: "runtime_workspace_rollback_failed",
        message: error.localizedDescription.ifBlank("iOS runtime workspace rollback failed"),
        error: error
      )
    }
  }

  private func packStatuses() -> [AgentRuntimePackStatus] {
    AgentRuntimePackCatalogPolicy.requiredPacks.map(packStatus)
  }

  private func packStatus(_ packId: String) -> AgentRuntimePackStatus {
    AgentIOSRuntimePackInstaller(
      runtimeRootURL: runtimeRootURL,
      fileManager: fileManager,
      signatureVerifier: signatureVerifier
    )
      .status(packId: packId)
  }

  private func packOutput(_ pack: AgentRuntimePackStatus) -> AgentMcpJSONObject {
    [
      "id": .string(pack.id),
      "state": .string(pack.state.rawValue),
      "reason": .string(pack.reason),
      "version": .string(pack.manifest?.version ?? ""),
      "architecture": .string(pack.manifest?.architecture ?? ""),
      "capabilities": .array((pack.manifest?.capabilities ?? []).sorted().map(AgentMcpJSONValue.string)),
      "installed_size_bytes": .int(pack.manifest?.installedSizeBytes ?? 0),
      "license": .string(pack.manifest?.license ?? ""),
      "recovery_required": .bool(false)
    ]
  }

  private func languageOutput(
    _ language: AgentRuntimeLanguage,
    packs: [AgentRuntimePackStatus],
    backendReady: Bool
  ) -> AgentMcpJSONObject {
    let pack = packs.first { $0.id == language.requiredPack }
    let packReady = pack?.state == .ready &&
      (pack?.manifest?.capabilities.contains(language.requiredCapability) == true)
    return [
      "id": .string(language.rawValue),
      "required_pack": .string(language.requiredPack),
      "required_capability": .string(language.requiredCapability),
      "ready": .bool(backendReady && packReady),
      "pack_ready": .bool(packReady)
    ]
  }

  private func runtimeSetupReason() -> String {
    broker.availability().reason.ifBlank("Enable and pair the local iOS runtime broker.")
  }

  private func inspectBroker(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    var output = statusOutput()
    guard availability(operation: .execute).status == .available else {
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "iOS on-device runtime inspected",
        metadata: baseMetadata()
      )
    }
    do {
      let brokerOutput = try broker.invoke(
        operation: .status,
        input: [:],
        context: invocation.context,
        deadlineEpochMillis: invocation.deadlineEpochMillis
      )
      output.merge(brokerOutput) { _, remote in remote }
      if output["backend_ready"]?.boolValue == true {
        _ = lifecycleStore.ready()
      } else {
        _ = lifecycleStore.failed(reason: output["reason"]?.stringValue ?? "Runtime broker is not ready")
      }
      output["lifecycle"] = .object(lifecycleOutput())
      output["backend"] = output["backend"] ?? .string("ios_runtime_broker")
      output["backend_ready"] = output["backend_ready"] ?? .bool(true)
      output["reason"] = output["reason"] ?? .string("The local iOS runtime broker is ready")
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "iOS on-device runtime broker inspected",
        metadata: baseMetadata(["broker": .string(broker.implementationId)])
      )
    } catch let error as AgentIOSRuntimeBrokerError {
      _ = lifecycleStore.failed(reason: error.localizedDescription)
      output["backend"] = .string("ios_runtime_broker")
      output["backend_ready"] = .bool(false)
      output["reason"] = .string(error.localizedDescription)
      output["lifecycle"] = .object(lifecycleOutput())
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "iOS on-device runtime broker is unavailable",
        metadata: baseMetadata([
          "broker": .string(broker.implementationId),
          "broker_error": .string(error.code)
        ])
      )
    } catch {
      _ = lifecycleStore.failed(reason: error.localizedDescription)
      output["backend"] = .string("ios_runtime_broker")
      output["backend_ready"] = .bool(false)
      output["reason"] = .string(error.localizedDescription)
      output["lifecycle"] = .object(lifecycleOutput())
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: "iOS on-device runtime broker is unavailable",
        metadata: baseMetadata(["broker": .string(broker.implementationId)])
      )
    }
  }

  private func executeWithBroker(
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    let availability = availability(operation: .execute)
    guard availability.status == .available else {
      return requiresSetup(
        code: "runtime_execute_requires_setup",
        message: availability.reason.ifBlank(runtimeSetupReason())
      )
    }
    do {
      let output = try broker.invoke(
        operation: .execute,
        input: input,
        context: invocation.context,
        deadlineEpochMillis: invocation.deadlineEpochMillis
      )
      return AgentNativeToolExecutionResult.success(
        output: output,
        message: output["message"]?.stringValue?.nonEmpty ?? "iOS on-device runtime execution completed",
        metadata: baseMetadata(["broker": .string(broker.implementationId)])
      )
    } catch let error as AgentIOSRuntimeBrokerError {
      return AgentNativeToolExecutionResult.failure(
        code: error.code,
        message: error.localizedDescription,
        retryable: error.retryable,
        details: baseMetadata(["broker": .string(broker.implementationId)])
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "runtime_broker_execution_failed",
        message: error.localizedDescription.ifBlank("The local iOS runtime broker failed"),
        retryable: true,
        details: baseMetadata(["broker": .string(broker.implementationId)])
      )
    }
  }

  private func workspaceId(_ context: AgentNativeToolInvocationContext) -> String {
    [
      context.attributes["workspace_id"],
      context.turnId,
      context.conversationId,
      context.invocationId
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? "default"
  }

  private func requiresSetup(
    code: String,
    message: String
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: code,
      message: message,
      retryable: true,
      details: baseMetadata([
        "requires_setup": .bool(true)
      ])
    )
  }

  private func workspaceFailure(
    code: String,
    message: String,
    error: Error
  ) -> AgentNativeToolExecutionResult {
    var metadata = baseMetadata()
    if let workspaceError = error as? AgentRuntimeProjectWorkspaceError {
      metadata["workspace_error_code"] = .string(workspaceError.code.rawValue)
    }
    return AgentNativeToolExecutionResult.failure(
      code: code,
      message: message,
      retryable: false,
      details: metadata
    )
  }

  private func baseMetadata(_ extra: AgentMcpJSONObject = [:]) -> AgentMcpJSONObject {
    [
      "implementation": .string(implementationId),
      "platform": .string("ios"),
      "sandbox": .string("paired_ios_jailbreak_runtime_broker"),
      "network_default": .string("disabled")
    ].merging(extra) { _, new in new }
  }

  private func hostArchitecture() -> String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }

  private let maxRollbackBytes: Int64 = 512 * 1_024 * 1_024
}
