import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSFfmpegTranscodePlannerBuildsTypedPlansForEveryAdvertisedFormat() throws {
    let expectedCodec: [AgentIOSMediaTargetFormat: String] = [
      .mp4: "mpeg4",
      .m4a: "aac",
      .wav: "pcm_s16le",
      .flac: "flac",
      .gif: "-loop",
      .png: "png",
      .jpg: "mjpeg"
    ]

    for format in AgentIOSMediaTargetFormat.allCases {
      let request = mediaTranscodeRequest(format)
      let destination = "outputs/result.\(format.fileExtension)"
      let plan = try AgentIOSFfmpegTranscodePlanner.create(
        request: request,
        sourcePath: "inputs/source.mov",
        destinationPath: destination
      )

      XCTAssertEqual(plan.sourcePath, "inputs/source.mov")
      XCTAssertEqual(plan.destinationPath, destination)
      XCTAssertTrue(plan.arguments.contains(expectedCodec[format] ?? ""))
      XCTAssertEqual(plan.arguments[try XCTUnwrap(plan.arguments.firstIndex(of: "-i")) + 1], "./inputs/source.mov")
      XCTAssertEqual(plan.arguments.last, "./\(destination)")
      XCTAssertFalse(plan.arguments.contains("sh"))
      XCTAssertFalse(plan.arguments.contains("-c"))
      XCTAssertFalse(plan.arguments.contains { $0.contains(";") || $0.contains("&&") || $0.contains("||") })
    }
  }

  func testAgentIOSFfmpegTranscodePlannerAppliesTrimScaleAndAudioBounds() throws {
    let plan = try AgentIOSFfmpegTranscodePlanner.create(
      request: mediaTranscodeRequest(.mp4).with(
        preset: "compact",
        startMillis: 1_250,
        durationMillis: 4_500,
        maxWidth: 1_280,
        maxHeight: 720,
        audioBitrateKbps: 128
      ),
      sourcePath: "inputs/my clip.mov",
      destinationPath: "outputs/my clip.mp4"
    )

    XCTAssertTrue(plan.arguments.windows(ofCount: 2).contains(["-ss", "1.25"]))
    XCTAssertTrue(plan.arguments.windows(ofCount: 2).contains(["-t", "4.5"]))
    XCTAssertTrue(plan.arguments.windows(ofCount: 2).contains(["-b:a", "128k"]))
    XCTAssertTrue(try XCTUnwrap(plan.arguments.first { $0.hasPrefix("scale=") }).contains("min(1280,iw)"))
    XCTAssertTrue(plan.arguments.contains("./inputs/my clip.mov"))
    XCTAssertTrue(plan.arguments.contains("./outputs/my clip.mp4"))
  }

  func testAgentIOSFfmpegTranscodePlannerRejectsUnsafeRequests() {
    let request = mediaTranscodeRequest(.mp4)

    XCTAssertThrowsError(try AgentIOSFfmpegTranscodePlanner.create(
      request: request,
      sourcePath: "../source.mov",
      destinationPath: "outputs/result.mp4"
    ))
    XCTAssertThrowsError(try AgentIOSFfmpegTranscodePlanner.create(
      request: request,
      sourcePath: "inputs/source.mp4",
      destinationPath: "inputs/source.mp4"
    ))
    XCTAssertThrowsError(try AgentIOSFfmpegTranscodePlanner.create(
      request: request,
      sourcePath: "inputs/source.mov",
      destinationPath: "outputs/result.gif"
    ))
    XCTAssertThrowsError(try AgentIOSFfmpegTranscodePlanner.create(
      request: request,
      sourcePath: "main.ffmpeg.json",
      destinationPath: "outputs/result.mp4"
    ))
    XCTAssertThrowsError(try AgentIOSFfmpegTranscodePlanner.create(
      request: request.with(audioBitrateKbps: 12),
      sourcePath: "inputs/source.mov",
      destinationPath: "outputs/result.mp4"
    ))
  }

  func testAgentIOSFfmpegTranscodePlannerPresetsBoundVideoResolution() throws {
    let compact = try AgentIOSFfmpegTranscodePlanner.create(
      request: mediaTranscodeRequest(.mp4).with(preset: "compact"),
      sourcePath: "inputs/source.mov",
      destinationPath: "outputs/compact.mp4"
    )
    let balanced = try AgentIOSFfmpegTranscodePlanner.create(
      request: mediaTranscodeRequest(.mp4).with(preset: "balanced"),
      sourcePath: "inputs/source.mov",
      destinationPath: "outputs/balanced.mp4"
    )
    let high = try AgentIOSFfmpegTranscodePlanner.create(
      request: mediaTranscodeRequest(.mp4).with(preset: "high_quality"),
      sourcePath: "inputs/source.mov",
      destinationPath: "outputs/high.mp4"
    )

    XCTAssertTrue(try XCTUnwrap(compact.arguments.first { $0.hasPrefix("scale=") }).contains("min(1280,iw)"))
    XCTAssertTrue(try XCTUnwrap(balanced.arguments.first { $0.hasPrefix("scale=") }).contains("min(1920,iw)"))
    XCTAssertTrue(try XCTUnwrap(high.arguments.first { $0.hasPrefix("scale=") }).contains("trunc(iw/2)*2"))
  }

  func testAgentIOSMediaExecutorNormalizesSourcePathTranscodeThroughPlanner() throws {
    final class PlanningProvider: AgentIOSMediaNativeToolProviding {
      var implementationId = "planning.provider"
      var request: AgentIOSMediaTranscodeRequest?

      func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability { .available }
      func inspectMetadata(contentUri: String, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
        .success(output: [:])
      }
      func handoffPlayback(contentUri: String, contentType: String, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
        .success(output: [:])
      }
      func transcode(
        request: AgentIOSMediaTranscodeRequest,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        self.request = request
        return .success(
          output: [
            "source_path": .string(request.sourcePath),
            "destination_path": .string(request.destinationPath),
            "size_bytes": .int(1),
            "sha256": .string(String(repeating: "b", count: 64)),
            "execution_duration_ms": .int(1),
            "artifacts": .array([]),
            "execution_receipt": .object([:])
          ]
        )
      }
    }

    let provider = PlanningProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: provider, nowMillis: { 2_000 })
    )
    let context = AgentNativeToolInvocationContext(
      invocationId: "media-plan-1",
      grantedPermissions: [
        AgentIOSMediaNativeToolCatalog.workspaceMediaPermission,
        AgentIOSMediaNativeToolCatalog.mediaRuntimePermission
      ],
      grantedConsents: [
        AgentIOSMediaNativeToolCatalog.contentUriReadConsent,
        AgentIOSMediaNativeToolCatalog.contentUriWriteConsent,
        AgentIOSMediaNativeToolCatalog.mediaTranscodeConsent
      ],
      attributes: ["workspace_id": "workspace-1"]
    )

    let success = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("inputs\\turn\\clip.mov"),
        "target_format": .string("mp4")
      ],
      context: context
    )
    let rejected = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("main.ffmpeg.json"),
        "target_format": .string("mp4")
      ],
      context: context
    )

    XCTAssertTrue(success.isSuccess)
    XCTAssertEqual(provider.request?.sourcePath, "inputs/turn/clip.mov")
    XCTAssertTrue(provider.request?.destinationPath.hasPrefix("outputs/media-") == true)
    XCTAssertTrue(provider.request?.destinationPath.hasSuffix(".mp4") == true)
    XCTAssertEqual(success.metadata["ffmpeg_network_enabled"], .bool(false))
    XCTAssertEqual(rejected.status, .failed)
    XCTAssertEqual(rejected.error?.code, "invalid_transcode_request")
  }

  private func mediaTranscodeRequest(_ format: AgentIOSMediaTargetFormat) -> AgentIOSMediaTranscodeRequest {
    AgentIOSMediaTranscodeRequest(
      contentUri: "",
      sourcePath: "inputs/source.mov",
      destinationPath: "outputs/result.\(format.fileExtension)",
      targetFormat: format.wireValue,
      preset: "balanced",
      startMillis: 0,
      durationMillis: 0,
      maxWidth: 0,
      maxHeight: 0,
      audioBitrateKbps: 0,
      timeoutMillis: 5 * 60_000,
      workspaceId: "workspace-1",
      invocationId: "invocation-1"
    )
  }
}

private extension AgentIOSMediaTranscodeRequest {
  func with(
    preset: String? = nil,
    startMillis: Int64? = nil,
    durationMillis: Int64? = nil,
    maxWidth: Int? = nil,
    maxHeight: Int? = nil,
    audioBitrateKbps: Int? = nil
  ) -> AgentIOSMediaTranscodeRequest {
    AgentIOSMediaTranscodeRequest(
      contentUri: contentUri,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      targetFormat: targetFormat,
      preset: preset ?? self.preset,
      startMillis: startMillis ?? self.startMillis,
      durationMillis: durationMillis ?? self.durationMillis,
      maxWidth: maxWidth ?? self.maxWidth,
      maxHeight: maxHeight ?? self.maxHeight,
      audioBitrateKbps: audioBitrateKbps ?? self.audioBitrateKbps,
      timeoutMillis: timeoutMillis,
      workspaceId: workspaceId,
      invocationId: invocationId
    )
  }
}

private extension Array where Element == String {
  func windows(ofCount count: Int) -> [[String]] {
    guard count > 0, self.count >= count else { return [] }
    return (0...(self.count - count)).map { index in
      Array(self[index..<(index + count)])
    }
  }
}
