import Foundation

struct AgentIOSOnDeviceFfmpegRuntimeAdapter: AgentIOSFfmpegRuntimeExecuting {
  var provider: AgentIOSOnDeviceRuntimeToolProviding
  var nowMillis: () -> Int64

  var implementationId: String {
    "\(provider.implementationId).ffmpeg"
  }

  init(
    provider: AgentIOSOnDeviceRuntimeToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.provider = provider
    self.nowMillis = nowMillis
  }

  func availability() -> AgentNativeToolAvailability {
    provider.availability(operation: .execute)
  }

  func execute(_ request: AgentIOSFfmpegRuntimeRequest) throws -> AgentIOSFfmpegRuntimeResult {
    let input = runtimeInput(request)
    let invocation = try runtimeInvocation(request: request, input: input)
    let result = provider.invoke(operation: .execute, input: input, invocation: invocation)
    guard result.isSuccess else {
      throw AgentIOSFfmpegMediaProviderError.ffmpegRuntimeFailed(
        result.error?.message.ifBlank(result.message) ?? result.message.ifBlank("iOS on-device runtime execution failed")
      )
    }
    return AgentIOSFfmpegRuntimeResult(
      exitCode: Int(result.output["exit_code"]?.intValue ?? -1),
      stderr: result.output["stderr"]?.stringValue ?? "",
      durationMillis: result.output["duration_ms"]?.intValue ?? 0,
      artifacts: result.output["artifacts"]?.arrayValue?.compactMap(\.objectValue) ?? [],
      executionReceipt: result.output["execution_receipt"]?.objectValue ?? [:]
    )
  }

  private func runtimeInput(_ request: AgentIOSFfmpegRuntimeRequest) -> AgentMcpJSONObject {
    [
      "language": .string(request.language),
      "source": .string(request.source),
      "arguments": .array(request.arguments.map(AgentMcpJSONValue.string)),
      "timeout_ms": .int(request.timeoutMillis),
      "network_enabled": .bool(false),
      "allowed_network_domains": .array([]),
      "artifact_paths": .array(request.artifactPaths.map(AgentMcpJSONValue.string))
    ]
  }

  private func runtimeInvocation(
    request: AgentIOSFfmpegRuntimeRequest,
    input: AgentMcpJSONObject
  ) throws -> AgentNativeToolInvocation {
    let descriptor = try AgentNativeToolDescriptor(
      id: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      version: AgentPhoneNativeToolCatalog.version,
      title: AgentIOSOnDeviceRuntimeNativeToolCatalog.title(.execute),
      description: "Run bounded FFmpeg work in the iOS-local runtime.",
      location: .application,
      inputSchema: AgentNativeToolDescriptor.objectSchema(),
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: .medium,
      capabilities: ["runtime.ios_local", "runtime.sandboxed", "media.transcode"],
      requiredPermissions: [],
      requiredConsents: [],
      timeoutMillis: request.timeoutMillis,
      idempotency: .nonIdempotent,
      availability: availability()
    )
    let startedAt = max(0, nowMillis())
    return AgentNativeToolInvocation(
      descriptor: descriptor,
      input: input,
      context: AgentNativeToolInvocationContext(
        invocationId: request.requestId,
        deadlineEpochMillis: startedAt + request.timeoutMillis,
        attributes: ["workspace_id": request.workspaceId]
      ),
      startedAtEpochMillis: startedAt,
      deadlineEpochMillis: startedAt + request.timeoutMillis,
      nowMillis: nowMillis,
      cancellationRequested: { false },
      progressReporter: { _, _ in }
    )
  }
}
