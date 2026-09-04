import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSMediaNativeToolCatalogAndExecutorBoundsMetadataPlaybackAndTranscode() throws {
    final class FakeMediaProvider: AgentIOSMediaNativeToolProviding {
      var implementationId = "fake.ios.media"
      var currentAvailability: AgentNativeToolAvailability = .available
      var metadataUri = ""
      var playbackUri = ""
      var playbackContentType = ""
      var transcodeRequest: AgentIOSMediaTranscodeRequest?
      var transcodeCalls = 0

      func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func inspectMetadata(
        contentUri: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        metadataUri = contentUri
        return AgentNativeToolExecutionResult.success(
          output: [
            "content_uri": .string(contentUri),
            "content_type": .string("video/mp4"),
            "display_name": .string("clip.mp4"),
            "size_bytes": .int(4_096),
            "duration_ms": .int(4_000),
            "width": .int(1_920),
            "height": .int(1_080),
            "rotation_degrees": .int(0),
            "has_audio": .bool(true),
            "has_video": .bool(true),
            "observed_at_epoch_ms": .int(1_000),
            "source": .object(["content_uri": .string(contentUri)])
          ]
        )
      }

      func handoffPlayback(
        contentUri: String,
        contentType: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        playbackUri = contentUri
        playbackContentType = contentType
        return AgentNativeToolExecutionResult.success(
          output: [
            "launched": .bool(true),
            "action": .string("ios.media.open"),
            "handler_package": .string("com.apple.avplayer"),
            "completed": .bool(false),
            "handed_off_at_epoch_ms": .int(1_000),
            "source": .object(["content_uri": .string(contentUri)])
          ]
        )
      }

      func transcode(
        request: AgentIOSMediaTranscodeRequest,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        transcodeCalls += 1
        transcodeRequest = request
        let sha = String(repeating: "a", count: 64)
        return AgentNativeToolExecutionResult.success(
          output: [
            "source_path": .string(request.sourcePath.isEmpty ? "selected/input.mov" : request.sourcePath),
            "destination_path": .string(request.destinationPath.isEmpty ? "outputs/clip.mp4" : request.destinationPath),
            "target_format": .string(request.targetFormat),
            "mime_type": .string("video/mp4"),
            "size_bytes": .int(8_192),
            "sha256": .string(sha),
            "execution_duration_ms": .int(250),
            "artifacts": .array([
              .object([
                "relative_path": .string("outputs/clip.mp4"),
                "size_bytes": .int(8_192),
                "sha256": .string(sha),
                "artifact_kind": .string("media")
              ])
            ]),
            "execution_receipt": .object(["runtime": .string("ffmpeg")]),
            "network_enabled": .bool(false),
            "completed_at_epoch_ms": .int(1_000)
          ]
        )
      }
    }

    let provider = FakeMediaProvider()
    let definitions = AgentIOSMediaNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: provider, nowMillis: { 2_000 })
    )
    let contentContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [AgentIOSMediaNativeToolCatalog.contentUriReadConsent]
    )
    let playbackContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [
        AgentIOSMediaNativeToolCatalog.contentUriReadConsent,
        AgentIOSMediaNativeToolCatalog.mediaPlaybackConsent
      ]
    )
    let transcodeContext = AgentNativeToolInvocationContext(
      invocationId: "media-transcode-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
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

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSMediaNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSMediaNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSMediaNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios_phone")
    }

    let metadata = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaMetadata,
      input: ["content_uri": .string("content://media/item-7")],
      context: contentContext
    )
    let deniedPlayback = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaPlaybackHandoff,
      input: ["content_uri": .string("content://media/item-7")],
      context: contentContext
    )
    let playback = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaPlaybackHandoff,
      input: [
        "content_uri": .string("content://media/item-7"),
        "content_type": .string("video/mp4")
      ],
      context: playbackContext
    )
    let transcode = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("inputs/turn/clip.mov"),
        "destination_path": .string("outputs/clip.mp4"),
        "target_format": .string("mp4"),
        "preset": .string("compact"),
        "timeout_ms": .int(30_000)
      ],
      context: transcodeContext
    )
    let duplicateSource = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "content_uri": .string("content://media/item-7"),
        "source_path": .string("inputs/turn/clip.mov"),
        "target_format": .string("mp4")
      ],
      context: transcodeContext
    )
    let unavailableProvider = FakeMediaProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install signed FFmpeg runtime"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("inputs/turn/clip.mov"),
        "target_format": .string("mp4")
      ],
      context: transcodeContext
    )

    XCTAssertTrue(metadata.isSuccess)
    XCTAssertEqual(metadata.output["duration_ms"], .int(4_000))
    XCTAssertEqual(metadata.output["has_video"], .bool(true))
    XCTAssertEqual(provider.metadataUri, "content://media/item-7")
    XCTAssertEqual(deniedPlayback.status, .rejected)
    XCTAssertEqual(deniedPlayback.error?.code, "missing_consents")
    XCTAssertTrue(playback.isSuccess)
    XCTAssertEqual(playback.output["launched"], .bool(true))
    XCTAssertEqual(playback.output["completed"], .bool(false))
    XCTAssertEqual(provider.playbackUri, "content://media/item-7")
    XCTAssertEqual(provider.playbackContentType, "video/mp4")
    XCTAssertTrue(transcode.isSuccess)
    XCTAssertEqual(provider.transcodeRequest?.workspaceId, "workspace-1")
    XCTAssertEqual(provider.transcodeRequest?.sourcePath, "inputs/turn/clip.mov")
    XCTAssertEqual(provider.transcodeRequest?.targetFormat, "mp4")
    XCTAssertEqual(provider.transcodeRequest?.preset, "compact")
    XCTAssertEqual(transcode.output["mime_type"], .string("video/mp4"))
    XCTAssertEqual(transcode.output["network_enabled"], .bool(false))
    XCTAssertEqual(duplicateSource.status, .failed)
    XCTAssertEqual(duplicateSource.error?.code, "invalid_transcode_source")
    XCTAssertEqual(provider.transcodeCalls, 1)
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertEqual(unavailableProvider.transcodeCalls, 0)
  }

  func testAgentIOSAVFoundationMediaProviderBridgesFileMetadataAndPlayback() throws {
    final class FakeMetadataInspector: AgentIOSMediaMetadataInspecting {
      var implementationId = "fake.ios.media_metadata"
      var availability: AgentNativeToolAvailability = .available
      var inspectedURL: URL?
      var inspectedContentUri = ""

      func inspect(fileURL: URL, contentUri: String) throws -> AgentIOSMediaMetadataSnapshot {
        inspectedURL = fileURL
        inspectedContentUri = contentUri
        return AgentIOSMediaMetadataSnapshot(
          contentUri: contentUri,
          contentType: "video/quicktime",
          displayName: "clip.mov",
          sizeBytes: 4,
          durationMillis: 12_345,
          width: 1_280,
          height: 720,
          rotationDegrees: 450,
          hasAudio: true,
          hasVideo: true
        )
      }
    }

    final class FakePlaybackOpener: AgentIOSMediaPlaybackOpening {
      var implementationId = "fake.ios.media_playback"
      var availability: AgentNativeToolAvailability = .available
      var openedURL: URL?
      var openedContentType = ""

      func open(fileURL: URL, contentType: String) throws -> AgentIOSMediaPlaybackOpenResult {
        openedURL = fileURL
        openedContentType = contentType
        return AgentIOSMediaPlaybackOpenResult(
          launched: true,
          action: "ios.media.open",
          handlerPackage: "com.apple.UIKit"
        )
      }
    }

    let root = try temporaryDirectory("ios-avfoundation-media-provider")
    defer { try? FileManager.default.removeItem(at: root) }
    let mediaURL = root.appendingPathComponent("clip.mov", isDirectory: false)
    try Data([0, 1, 2, 3]).write(to: mediaURL)

    let inspector = FakeMetadataInspector()
    let opener = FakePlaybackOpener()
    let provider = AgentIOSAVFoundationMediaProvider(
      metadataInspector: inspector,
      playbackOpener: opener,
      nowMillis: { 9_000 }
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: provider, nowMillis: { 9_500 })
    )
    let contentContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [AgentIOSMediaNativeToolCatalog.contentUriReadConsent]
    )
    let playbackContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [
        AgentIOSMediaNativeToolCatalog.contentUriReadConsent,
        AgentIOSMediaNativeToolCatalog.mediaPlaybackConsent
      ]
    )
    let fileUri = mediaURL.absoluteString

    let metadata = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaMetadata,
      input: ["content_uri": .string(fileUri)],
      context: contentContext
    )
    let playback = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaPlaybackHandoff,
      input: [
        "content_uri": .string(fileUri),
        "content_type": .string("video/quicktime")
      ],
      context: playbackContext
    )
    let androidOnlyContentUri = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaMetadata,
      input: ["content_uri": .string("content://media/item-7")],
      context: contentContext
    )

    XCTAssertTrue(metadata.isSuccess)
    XCTAssertEqual(inspector.inspectedURL?.standardizedFileURL, mediaURL.standardizedFileURL)
    XCTAssertEqual(inspector.inspectedContentUri, fileUri)
    XCTAssertEqual(metadata.output["content_type"], .string("video/quicktime"))
    XCTAssertEqual(metadata.output["duration_ms"], .int(12_345))
    XCTAssertEqual(metadata.output["rotation_degrees"], .int(90))
    XCTAssertEqual(metadata.output["observed_at_epoch_ms"], .int(9_000))
    XCTAssertEqual(metadata.metadata["media_implementation"], .string("fake.ios.media_metadata"))
    XCTAssertEqual(metadata.metadata["media_provider"], .string("galaxyssi.ios.avfoundation_media"))
    XCTAssertTrue(playback.isSuccess)
    XCTAssertEqual(opener.openedURL?.standardizedFileURL, mediaURL.standardizedFileURL)
    XCTAssertEqual(opener.openedContentType, "video/quicktime")
    XCTAssertEqual(playback.output["launched"], .bool(true))
    XCTAssertEqual(playback.output["completed"], .bool(false))
    XCTAssertEqual(playback.metadata["playback_implementation"], .string("fake.ios.media_playback"))
    XCTAssertEqual(androidOnlyContentUri.status, .failed)
    XCTAssertEqual(androidOnlyContentUri.error?.code, "unsupported_content_uri")
  }

}
