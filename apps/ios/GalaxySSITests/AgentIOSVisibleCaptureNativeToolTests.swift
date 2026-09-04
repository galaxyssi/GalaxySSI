import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSVisibleCaptureNativeToolCatalogAndExecutorRequiresForegroundReceipts() throws {
    final class FakeVisibleCaptureProvider: AgentIOSVisibleCaptureToolProviding {
      var implementationId = "fake.ios.visible_capture"
      var currentAvailability: AgentNativeToolAvailability = .available
      var photoCalls = 0
      var audioCalls = 0
      var capturedFacing = ""
      var capturedAudioDuration = 0

      func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func capturePhoto(
        facing: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentIOSVisibleCaptureOutcome {
        photoCalls += 1
        capturedFacing = facing
        return AgentIOSVisibleCaptureOutcome(
          status: .succeeded,
          artifact: AgentIOSVisibleCaptureArtifact(
            kind: .photo,
            contentUri: "content://galaxyssi.test/photo/1",
            mimeType: "image/jpeg",
            sizeBytes: 8_192,
            widthPixels: 1_920,
            heightPixels: 1_080,
            capturedAtEpochMillis: 1_000,
            completedBy: "autofocus_capture"
          )
        )
      }

      func recordAudio(
        maxDurationSeconds: Int,
        invocation: AgentNativeToolInvocation
      ) -> AgentIOSVisibleCaptureOutcome {
        audioCalls += 1
        capturedAudioDuration = maxDurationSeconds
        return AgentIOSVisibleCaptureOutcome(
          status: .succeeded,
          artifact: AgentIOSVisibleCaptureArtifact(
            kind: .audio,
            contentUri: "content://galaxyssi.test/audio/1",
            mimeType: "audio/mp4",
            sizeBytes: 4_096,
            durationMillis: Int64(maxDurationSeconds * 1_000),
            capturedAtEpochMillis: 1_000,
            completedBy: "max_duration"
          )
        )
      }
    }

    let provider = FakeVisibleCaptureProvider()
    let definitions = AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.visibleCaptureExecutableDefinitions(provider: provider)
    )
    let photoContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSVisibleCaptureNativeToolCatalog.cameraPermission],
      grantedConsents: [
        AgentIOSVisibleCaptureNativeToolCatalog.runtimePermissionConsent,
        AgentIOSVisibleCaptureNativeToolCatalog.userVisibleCaptureConsent
      ]
    )
    let audioContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSVisibleCaptureNativeToolCatalog.microphonePermission],
      grantedConsents: [
        AgentIOSVisibleCaptureNativeToolCatalog.runtimePermissionConsent,
        AgentIOSVisibleCaptureNativeToolCatalog.userVisibleCaptureConsent
      ]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSVisibleCaptureNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.risk, .high)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertEqual(definition.provenanceMetadata["background_capture"], "false")
      XCTAssertEqual(definition.provenanceMetadata["artifact_contract"], "content-uri-v1")
      XCTAssertTrue(definition.descriptor.requiredConsents.contains {
        $0.id == AgentIOSVisibleCaptureNativeToolCatalog.userVisibleCaptureConsent
      })
    }

    let denied = registry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
      input: ["facing": .string("front")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSVisibleCaptureNativeToolCatalog.cameraPermission],
        grantedConsents: [AgentIOSVisibleCaptureNativeToolCatalog.runtimePermissionConsent]
      )
    )
    let photo = registry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
      input: ["facing": .string("front")],
      context: photoContext
    )
    let audio = registry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord,
      input: ["max_duration_seconds": .int(2)],
      context: audioContext
    )
    let unavailableProvider = FakeVisibleCaptureProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .unavailable,
      reason: "No capture hardware"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.visibleCaptureExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
      input: ["facing": .string("back")],
      context: photoContext
    )

    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_consents")
    XCTAssertEqual(provider.photoCalls, 1)
    XCTAssertTrue(photo.isSuccess)
    XCTAssertEqual(provider.capturedFacing, "front")
    XCTAssertEqual(photo.output["kind"], .string("photo"))
    XCTAssertEqual(photo.output["content_uri"], .string("content://galaxyssi.test/photo/1"))
    XCTAssertEqual(photo.output["user_visible"], .bool(true))
    XCTAssertEqual(photo.metadata["background_capture"], .bool(false))
    XCTAssertEqual(photo.metadata["raw_media_in_receipt"], .bool(false))
    XCTAssertEqual(photo.verification?.status, .passed)
    XCTAssertTrue(audio.isSuccess)
    XCTAssertEqual(provider.audioCalls, 1)
    XCTAssertEqual(provider.capturedAudioDuration, 2)
    XCTAssertEqual(audio.output["kind"], .string("audio"))
    XCTAssertEqual(audio.output["duration_ms"], .int(2_000))
    XCTAssertEqual(audio.output["user_visible"], .bool(true))
    XCTAssertEqual(audio.verification?.status, .passed)
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertEqual(unavailableProvider.photoCalls, 0)
  }

  func testAgentIOSVisibleCaptureDefaultsUseForegroundNativeProvider() throws {
    let definitions = AgentIOSVisibleCaptureNativeToolCatalog.definitions()

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    XCTAssertEqual(
      Set(definitions.compactMap { $0.provenanceMetadata["implementation"] }),
      ["galaxyssi.ios.visible_capture.uikit_avfoundation"]
    )
    XCTAssertTrue(definitions.allSatisfy {
      $0.provenanceMetadata["capture_surface"] == "foreground_user_visible_ios"
    })
  }

  func testAgentIOSVisibleCaptureArtifactStoreWritesInsideBoundedRoot() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("GalaxySSITest-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: rootURL)
    }
    let store = AgentIOSVisibleCaptureArtifactStore(rootURL: rootURL)
    let artifactURL = try store.makeArtifactURL(
      kind: .photo,
      fileExtension: "jpg",
      requestId: "../capture request"
    )

    XCTAssertTrue(artifactURL.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path))
    XCTAssertTrue(artifactURL.lastPathComponent.hasSuffix(".jpg"))
    XCTAssertFalse(artifactURL.lastPathComponent.contains(".."))

    try Data([1, 2, 3, 4]).write(to: artifactURL)
    XCTAssertEqual(try store.fileSize(artifactURL), 4)
  }

}
