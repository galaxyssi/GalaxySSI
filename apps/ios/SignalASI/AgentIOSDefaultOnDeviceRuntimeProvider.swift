import Foundation

struct AgentIOSDefaultOnDeviceRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding {
  var implementationId: String = "signalasi.ios.default_runtime_status"

  private let runtimeRootURL: URL
  private let workspaceManager: AgentRuntimeProjectWorkspaceManager
  private let fileManager: FileManager
  private let nowMillis: () -> Int64
  private let catalogManager: AgentIOSRuntimePackCatalogManager
  private let signatureVerifier: (AgentRuntimePackManifest) -> Bool

  var runtimeWorkspaceManager: AgentRuntimeProjectWorkspaceManager? {
    workspaceManager
  }

  init(
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    workspaceManager: AgentRuntimeProjectWorkspaceManager? = nil,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
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
  }

  static func defaultRuntimeRootURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL.appendingPathComponent("on-device-runtime", isDirectory: true)
  }

  func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
    switch operation {
    case .status, .workspaceStatus, .workspaceRollback, .listPacks:
      return .available
    case .installPack:
      return .available
    case .execute:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: runtimeSetupReason(packStatuses())
      )
    }
  }

  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    switch operation {
    case .status:
      return AgentNativeToolExecutionResult.success(
        output: statusOutput(),
        message: "iOS on-device runtime inspected",
        metadata: baseMetadata()
      )
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
    case .execute:
      return requiresSetup(
        code: "runtime_execute_requires_setup",
        message: runtimeSetupReason(packStatuses())
      )
    }
  }

  private func statusOutput() -> AgentMcpJSONObject {
    let packs = packStatuses()
    let reason = runtimeSetupReason(packs)
    let backendReady = false
    let linuxBaseRecoveryRequired = requiresLinuxBaseRecovery(packs)
    return [
      "backend": .string("none"),
      "backend_ready": .bool(backendReady),
      "reason": .string(reason),
      "architecture": .string(hostArchitecture()),
      "avf_advertised": .bool(false),
      "lifecycle": .object([
        "phase": .string("requires_setup"),
        "reason": .string(reason),
        "consecutive_failures": .int(0),
        "next_attempt_at_millis": .int(0)
      ]),
      "packs": .array(packs.map { .object(packOutput($0)) }),
      "languages": .array(AgentRuntimeLanguage.allCases.map {
        .object(languageOutput($0, packs: packs, backendReady: backendReady))
      }),
      "observed_at_epoch_ms": .int(max(0, nowMillis())),
      "runtime_store": .string("app_private_application_support"),
      "execution_target": .string("ios"),
      "linux_base_recovery_baseline": .string(AgentRuntimePackCatalogPolicy.linuxBaseRecoveryVersion),
      "linux_base_recovery_required": .bool(linuxBaseRecoveryRequired)
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
      "recovery_required": .bool(
        pack.id == "linux-base" &&
          (pack.state != .ready ||
            !AgentRuntimePackCatalogPolicy.meetsLinuxBaseRecoveryBaseline(pack.manifest?.version ?? ""))
      )
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

  private func runtimeSetupReason(_ packs: [AgentRuntimePackStatus]) -> String {
    guard let linuxBase = packs.first(where: { $0.id == "linux-base" }), linuxBase.state == .ready else {
      return "Install the linux-base runtime pack and connect a signed iOS runtime broker"
    }
    guard AgentRuntimePackCatalogPolicy.meetsLinuxBaseRecoveryBaseline(linuxBase.manifest?.version ?? "") else {
      return "Recover the signed linux-base \(AgentRuntimePackCatalogPolicy.linuxBaseRecoveryVersion) runtime pack and connect a signed iOS runtime broker"
    }
    return "Signed iOS runtime broker is not connected"
  }

  private func requiresLinuxBaseRecovery(_ packs: [AgentRuntimePackStatus]) -> Bool {
    guard let linuxBase = packs.first(where: { $0.id == "linux-base" }),
          linuxBase.state == .ready else {
      return true
    }
    return !AgentRuntimePackCatalogPolicy.meetsLinuxBaseRecoveryBaseline(linuxBase.manifest?.version ?? "")
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
      "sandbox": .string("ios_app_private_runtime_store"),
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
