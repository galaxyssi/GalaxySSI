import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSOnDeviceFfmpegRuntimeAdapterInvokesRuntimeExecuteWithBoundedInput() throws {
    let provider = FakeIOSOnDeviceRuntimeProvider(
      responses: [
        .success(
          output: [
            "exit_code": .int(0),
            "stderr": .string(""),
            "duration_ms": .int(456),
            "artifacts": .array([
              .object([
                "relative_path": .string("outputs/clip.mp4"),
                "size_bytes": .int(12),
                "sha256": .string(String(repeating: "c", count: 64))
              ])
            ]),
            "execution_receipt": .object(["runtime": .string("ios-local")])
          ]
        )
      ]
    )
    let adapter = AgentIOSOnDeviceFfmpegRuntimeAdapter(provider: provider, nowMillis: { 1_000 })
    let request = iosFfmpegRuntimeRequest()

    let result = try adapter.execute(request)
    let call = try XCTUnwrap(provider.calls.first)

    XCTAssertEqual(adapter.availability().status, .available)
    XCTAssertEqual(adapter.implementationId, "fake.ios.runtime.ffmpeg")
    XCTAssertEqual(provider.calls.count, 1)
    XCTAssertEqual(call.operation, .execute)
    XCTAssertEqual(call.input["language"], .string("ffmpeg"))
    XCTAssertEqual(call.input["source"], .string(#"{"operation":"media_transcode"}"#))
    XCTAssertEqual(call.input["timeout_ms"], .int(30_000))
    XCTAssertEqual(call.input["network_enabled"], .bool(false))
    XCTAssertEqual(call.input["allowed_network_domains"], .array([]))
    XCTAssertEqual(call.input["arguments"], .array(["-i", "./inputs/clip.mov", "./outputs/clip.mp4"].map(AgentMcpJSONValue.string)))
    XCTAssertEqual(call.input["artifact_paths"], .array(["outputs/clip.mp4"].map(AgentMcpJSONValue.string)))
    XCTAssertEqual(call.invocation.context.invocationId, "media-runtime-1")
    XCTAssertEqual(call.invocation.context.attributes["workspace_id"], "workspace-1")
    XCTAssertEqual(call.invocation.startedAtEpochMillis, 1_000)
    XCTAssertEqual(call.invocation.deadlineEpochMillis, 31_000)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.durationMillis, 456)
    XCTAssertEqual(result.artifacts.first?["relative_path"], .string("outputs/clip.mp4"))
    XCTAssertEqual(result.executionReceipt, ["runtime": .string("ios-local")])
  }

  func testAgentIOSOnDeviceFfmpegRuntimeAdapterMapsProviderFailures() throws {
    let provider = FakeIOSOnDeviceRuntimeProvider(
      responses: [
        .failure(code: "runtime_provider_unavailable", message: "Runtime broker offline", retryable: true)
      ]
    )
    provider.availabilityValue = AgentNativeToolAvailability(status: .requiresSetup, reason: "Install runtime")
    let adapter = AgentIOSOnDeviceFfmpegRuntimeAdapter(provider: provider)

    XCTAssertEqual(adapter.availability().status, .requiresSetup)
    XCTAssertThrowsError(try adapter.execute(iosFfmpegRuntimeRequest())) { error in
      XCTAssertEqual(error as? AgentIOSFfmpegMediaProviderError, .ffmpegRuntimeFailed("Runtime broker offline"))
    }
  }

  func testAgentPhoneNativeToolCatalogDefaultRegistryWiresMediaThroughOnDeviceRuntime() throws {
    let runtimeProvider = FakeIOSOnDeviceRuntimeProvider(responses: [])
    runtimeProvider.availabilityValue = AgentNativeToolAvailability(status: .available, reason: "Runtime ready")
    let registry = try AgentPhoneNativeToolCatalog.createRegistry(
      actionExecutor: TestAgentActionExecutor { action, _ in
        AgentActionResult(actionId: action.id, success: true, message: "unused")
      },
      screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent") },
      capabilityStatusProvider: { readyPhoneCapabilityStatuses() },
      onDeviceRuntimeProvider: runtimeProvider
    )

    let mediaDefinition = try XCTUnwrap(registry.lookup(AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode))

    XCTAssertEqual(mediaDefinition.availabilityProvider.current().status, .available)
    XCTAssertEqual(mediaDefinition.availabilityProvider.current().reason, "Runtime ready")
    XCTAssertEqual(mediaDefinition.provenanceMetadata["implementation"], "galaxyssi.ios_runtime.ffmpeg")
  }

  private func iosFfmpegRuntimeRequest() -> AgentIOSFfmpegRuntimeRequest {
    AgentIOSFfmpegRuntimeRequest(
      language: "ffmpeg",
      source: #"{"operation":"media_transcode"}"#,
      arguments: ["-i", "./inputs/clip.mov", "./outputs/clip.mp4"],
      timeoutMillis: 30_000,
      networkEnabled: false,
      artifactPaths: ["outputs/clip.mp4"],
      workspaceId: "workspace-1",
      workspaceURL: FileManager.default.temporaryDirectory,
      requestId: "media-runtime-1",
      resourceLimits: AgentIOSFfmpegRuntimeResourceLimits(
        wallClockMillis: 30_000,
        cpuMillis: 27_000,
        memoryBytes: 768 * 1_024 * 1_024,
        diskBytes: 768 * 1_024 * 1_024,
        maxProcesses: 32,
        maxOutputBytes: 512 * 1_024,
        maxArtifactBytes: 256 * 1_024 * 1_024
      )
    )
  }
}

private final class FakeIOSOnDeviceRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding {
  struct Call {
    var operation: AgentIOSOnDeviceRuntimeToolOperation
    var input: AgentMcpJSONObject
    var invocation: AgentNativeToolInvocation
  }

  var implementationId = "fake.ios.runtime"
  var availabilityValue = AgentNativeToolAvailability.available
  var calls: [Call] = []
  private var responses: [AgentNativeToolExecutionResult]

  init(responses: [AgentNativeToolExecutionResult]) {
    self.responses = responses
  }

  func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
    availabilityValue
  }

  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    calls.append(Call(operation: operation, input: input, invocation: invocation))
    guard !responses.isEmpty else {
      return .failure(code: "missing_fake_response", message: "No fake runtime response queued")
    }
    return responses.removeFirst()
  }
}
