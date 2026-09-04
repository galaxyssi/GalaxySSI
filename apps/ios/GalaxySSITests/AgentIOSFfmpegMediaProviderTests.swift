import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSSignedFfmpegMediaProviderExecutesPlannedSourcePathTranscode() throws {
    let root = try temporaryDirectory("ios-ffmpeg-provider-source")
    defer { try? FileManager.default.removeItem(at: root) }
    let workspaceId = "workspace-1"
    let source = root
      .appendingPathComponent(workspaceId, isDirectory: true)
      .appendingPathComponent("inputs/turn/clip.mov", isDirectory: false)
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("source-media".utf8).write(to: source)

    let runtime = FakeIOSFfmpegRuntime(outputData: Data("converted-media".utf8))
    let provider = AgentIOSSignedFfmpegMediaProvider(
      runtime: runtime,
      projectRoot: root,
      nowMillis: { 12_345 }
    )
    let request = iosFfmpegMediaRequest(
      workspaceId: workspaceId,
      sourcePath: "inputs/turn/clip.mov",
      destinationPath: "outputs/clip.mp4",
      preset: "compact",
      invocationId: "media-provider-1"
    )

    let result = provider.transcode(request: request, invocation: try mediaInvocation())
    let runtimeRequest = try XCTUnwrap(runtime.requests.first)

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(runtime.requests.count, 1)
    XCTAssertEqual(runtimeRequest.language, "ffmpeg")
    XCTAssertEqual(runtimeRequest.workspaceId, workspaceId)
    XCTAssertEqual(runtimeRequest.workspaceURL.standardizedFileURL, root.appendingPathComponent(workspaceId, isDirectory: true).standardizedFileURL)
    XCTAssertEqual(runtimeRequest.networkEnabled, false)
    XCTAssertEqual(runtimeRequest.artifactPaths, ["outputs/clip.mp4"])
    XCTAssertEqual(runtimeRequest.resourceLimits.memoryBytes, 768 * 1_024 * 1_024)
    XCTAssertEqual(runtimeRequest.arguments.last, "./outputs/clip.mp4")
    XCTAssertTrue(runtimeRequest.source.contains(#""operation":"media_transcode""#))
    XCTAssertTrue(runtimeRequest.source.contains(#""network_enabled":false"#))
    XCTAssertEqual(result.output["source_path"], .string("inputs/turn/clip.mov"))
    XCTAssertEqual(result.output["destination_path"], .string("outputs/clip.mp4"))
    XCTAssertEqual(result.output["mime_type"], .string("video/mp4"))
    XCTAssertEqual(result.output["sha256"], .string(GalaxySSIAttachmentPayloadBuilder.sha256(Data("converted-media".utf8))))
    XCTAssertEqual(result.output["completed_at_epoch_ms"], .int(12_345))
    XCTAssertEqual(result.metadata["runtime_implementation"], .string("fake.ios.ffmpeg"))
    XCTAssertEqual(result.metadata["workspace_path_redacted"], .bool(true))
  }

  func testAgentIOSSignedFfmpegMediaProviderImportsFileURLMediaIntoWorkspace() throws {
    let root = try temporaryDirectory("ios-ffmpeg-provider-import")
    let pickedDirectory = try temporaryDirectory("ios-ffmpeg-provider-picked")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: pickedDirectory)
    }
    let pickedFile = pickedDirectory.appendingPathComponent("Picked Clip.MOV", isDirectory: false)
    try Data("picked-media".utf8).write(to: pickedFile)
    let runtime = FakeIOSFfmpegRuntime(outputData: Data("converted-from-file-url".utf8))
    let provider = AgentIOSSignedFfmpegMediaProvider(runtime: runtime, projectRoot: root)
    let request = iosFfmpegMediaRequest(
      workspaceId: "workspace-2",
      contentUri: pickedFile.absoluteString,
      sourcePath: "",
      destinationPath: "",
      invocationId: "media-provider-2"
    )

    let result = provider.transcode(request: request, invocation: try mediaInvocation())
    let runtimeRequest = try XCTUnwrap(runtime.requests.first)
    let sourcePath = try XCTUnwrap(result.output["source_path"]?.stringValue)
    let imported = runtimeRequest.workspaceURL.appendingPathComponent(sourcePath, isDirectory: false)
    let destination = try XCTUnwrap(result.output["destination_path"]?.stringValue)

    XCTAssertTrue(result.isSuccess)
    XCTAssertTrue(sourcePath.hasPrefix("inputs/media/media-"))
    XCTAssertTrue(sourcePath.hasSuffix(".mov"))
    XCTAssertEqual(try Data(contentsOf: imported), Data("picked-media".utf8))
    XCTAssertTrue(destination.hasPrefix("outputs/media-"))
    XCTAssertTrue(destination.hasSuffix(".mp4"))
    XCTAssertEqual(runtimeRequest.arguments[try XCTUnwrap(runtimeRequest.arguments.firstIndex(of: "-i")) + 1], "./\(sourcePath)")
    XCTAssertEqual(runtimeRequest.artifactPaths, [destination])
  }

  func testAgentIOSSignedFfmpegMediaProviderMapsRuntimeAndOutputFailures() throws {
    let root = try temporaryDirectory("ios-ffmpeg-provider-failures")
    defer { try? FileManager.default.removeItem(at: root) }
    let workspaceId = "workspace-3"
    let source = root
      .appendingPathComponent(workspaceId, isDirectory: true)
      .appendingPathComponent("inputs/turn/clip.mov", isDirectory: false)
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("source-media".utf8).write(to: source)

    let unavailableRuntime = FakeIOSFfmpegRuntime(outputData: Data())
    unavailableRuntime.availabilityValue = AgentNativeToolAvailability(status: .requiresSetup, reason: "Install signed FFmpeg")
    let unavailable = AgentIOSSignedFfmpegMediaProvider(runtime: unavailableRuntime, projectRoot: root)
      .transcode(
        request: iosFfmpegMediaRequest(workspaceId: workspaceId, sourcePath: "inputs/turn/clip.mov"),
        invocation: try mediaInvocation()
      )

    let failingRuntime = FakeIOSFfmpegRuntime(outputData: Data(), exitCode: 1, stderr: "bad input\nencoder failed")
    let failed = AgentIOSSignedFfmpegMediaProvider(runtime: failingRuntime, projectRoot: root)
      .transcode(
        request: iosFfmpegMediaRequest(workspaceId: workspaceId, sourcePath: "inputs/turn/clip.mov"),
        invocation: try mediaInvocation()
      )

    let missingOutputRuntime = FakeIOSFfmpegRuntime(outputData: Data(), writesOutput: false)
    let missing = AgentIOSSignedFfmpegMediaProvider(runtime: missingOutputRuntime, projectRoot: root)
      .transcode(
        request: iosFfmpegMediaRequest(workspaceId: workspaceId, sourcePath: "inputs/turn/clip.mov"),
        invocation: try mediaInvocation()
      )

    XCTAssertEqual(unavailable.error?.code, "ffmpeg_requires_setup")
    XCTAssertEqual(unavailable.error?.retryable, true)
    XCTAssertTrue(unavailableRuntime.requests.isEmpty)
    XCTAssertEqual(failed.error?.code, "ffmpeg_transcode_failed")
    XCTAssertEqual(failed.error?.message, "FFmpeg could not convert the selected media: encoder failed")
    XCTAssertEqual(failed.error?.details["exit_code"], .int(1))
    XCTAssertEqual(failed.error?.details["execution_receipt"], .object(["runtime": .string("fake-ffmpeg")]))
    XCTAssertEqual(missing.error?.code, "ffmpeg_output_missing")
  }

  func testAgentIOSSignedFfmpegMediaProviderRejectsUnsafeWorkspaceSources() throws {
    let root = try temporaryDirectory("ios-ffmpeg-provider-unsafe")
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = AgentIOSSignedFfmpegMediaProvider(runtime: FakeIOSFfmpegRuntime(outputData: Data()), projectRoot: root)

    let unsafeWorkspace = provider.transcode(
      request: iosFfmpegMediaRequest(workspaceId: "../workspace", sourcePath: "inputs/turn/clip.mov"),
      invocation: try mediaInvocation()
    )
    let missingSource = provider.transcode(
      request: iosFfmpegMediaRequest(workspaceId: "workspace-4", sourcePath: "inputs/turn/missing.mov"),
      invocation: try mediaInvocation()
    )
    let contentUri = provider.transcode(
      request: iosFfmpegMediaRequest(
        workspaceId: "workspace-4",
        contentUri: "content://media/item-1",
        sourcePath: ""
      ),
      invocation: try mediaInvocation()
    )

    XCTAssertEqual(unsafeWorkspace.error?.code, "invalid_media_workspace")
    XCTAssertEqual(missingSource.error?.code, "media_source_not_found")
    XCTAssertEqual(contentUri.error?.code, "content_uri_required")
  }

  private func iosFfmpegMediaRequest(
    workspaceId: String,
    contentUri: String = "",
    sourcePath: String = "inputs/turn/clip.mov",
    destinationPath: String = "outputs/clip.mp4",
    targetFormat: String = "mp4",
    preset: String = "balanced",
    invocationId: String = "media-provider-test"
  ) -> AgentIOSMediaTranscodeRequest {
    AgentIOSMediaTranscodeRequest(
      contentUri: contentUri,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      targetFormat: targetFormat,
      preset: preset,
      startMillis: 0,
      durationMillis: 0,
      maxWidth: 0,
      maxHeight: 0,
      audioBitrateKbps: 0,
      timeoutMillis: 5 * 60_000,
      workspaceId: workspaceId,
      invocationId: invocationId
    )
  }

  private func mediaInvocation() throws -> AgentNativeToolInvocation {
    let descriptor = try AgentNativeToolDescriptor(
      id: AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      version: AgentPhoneNativeToolCatalog.version,
      title: "Transcode media",
      description: "Convert one local media file.",
      risk: .medium
    )
    return AgentNativeToolInvocation(
      descriptor: descriptor,
      input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "media-provider-invocation"),
      startedAtEpochMillis: 0,
      deadlineEpochMillis: 300_000,
      nowMillis: { 1_000 },
      cancellationRequested: { false },
      progressReporter: { _, _ in }
    )
  }
}

private final class FakeIOSFfmpegRuntime: AgentIOSFfmpegRuntimeExecuting {
  var implementationId = "fake.ios.ffmpeg"
  var availabilityValue = AgentNativeToolAvailability.available
  var requests: [AgentIOSFfmpegRuntimeRequest] = []
  var outputData: Data
  var exitCode: Int
  var stderr: String
  var writesOutput: Bool

  init(
    outputData: Data,
    exitCode: Int = 0,
    stderr: String = "",
    writesOutput: Bool = true
  ) {
    self.outputData = outputData
    self.exitCode = exitCode
    self.stderr = stderr
    self.writesOutput = writesOutput
  }

  func availability() -> AgentNativeToolAvailability {
    availabilityValue
  }

  func execute(_ request: AgentIOSFfmpegRuntimeRequest) throws -> AgentIOSFfmpegRuntimeResult {
    requests.append(request)
    let artifactPath = request.artifactPaths.first ?? "outputs/clip.mp4"
    if exitCode == 0 && writesOutput {
      let outputURL = request.workspaceURL.appendingPathComponent(artifactPath, isDirectory: false)
      try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try outputData.write(to: outputURL)
    }
    let artifacts: [AgentMcpJSONObject] = writesOutput ? [[
      "relative_path": .string(artifactPath),
      "size_bytes": .int(Int64(outputData.count)),
      "sha256": .string(GalaxySSIAttachmentPayloadBuilder.sha256(outputData)),
      "artifact_kind": .string("media")
    ]] : []
    return AgentIOSFfmpegRuntimeResult(
      exitCode: exitCode,
      stderr: stderr,
      durationMillis: 321,
      artifacts: artifacts,
      executionReceipt: ["runtime": .string("fake-ffmpeg")]
    )
  }
}
