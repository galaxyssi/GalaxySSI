import XCTest
@testable import GalaxySSI

// Readiness-only fixtures never open a permission dialog, camera or microphone.
final class AgentCaptureReadinessTests: XCTestCase {
  func testCaptureDefinitionsPreserveExplicitEagerCalls() {
    let provider = Provider()
    let definitions = AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider)
    XCTAssertEqual(provider.probes, [.photo, .audio])
    XCTAssertEqual(definitions.count, 2)
  }

  func testCaptureDeferredRegistrationAvoidsPermissionProbes() throws {
    let provider = Provider()
    let definitions = AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider,
      initialAvailability: AgentIOSVisibleCaptureNativeToolCatalog.uncheckedAvailability)
    XCTAssertTrue(definitions.allSatisfy { $0.descriptor.availability == AgentIOSVisibleCaptureNativeToolCatalog.uncheckedAvailability })
    let registry = try AgentNativeToolRegistry().registerAll(definitions)
    _ = registry.registeredContractFingerprint()
    XCTAssertTrue(provider.probes.isEmpty)
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .available })
    XCTAssertEqual(provider.probes.count, 2)
    XCTAssertEqual(provider.captures, 0)
  }

  func testCaptureExecutableHelperForwardsDeferredInitialState() throws {
    let provider = Provider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.visibleCaptureExecutableDefinitions(provider: provider,
        initialAvailability: AgentIOSVisibleCaptureNativeToolCatalog.uncheckedAvailability))
    _ = registry.registeredContractFingerprint()
    XCTAssertTrue(provider.probes.isEmpty)
    _ = registry.descriptors()
    XCTAssertEqual(provider.probes.count, 2)
    XCTAssertEqual(provider.captures, 0)
  }

  func testCaptureRefreshRecoversAfterBusyAndDenial() throws {
    let provider = Provider()
    provider.busy = true
    let registry = try AgentNativeToolRegistry().registerAll(AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider))
    let fingerprint = registry.registeredContractFingerprint()
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.reason == "Fixture capture busy" })
    provider.busy = false
    registry.refreshAvailability()
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .available })
    provider.photo = .init(status: .requiresSetup, reason: "Fixture permission denied")
    provider.audio = provider.photo
    registry.refreshAvailability()
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .requiresSetup })
    provider.photo = .available
    provider.audio = .available
    registry.refreshAvailability()
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .available })
    XCTAssertEqual(registry.registeredContractFingerprint(), fingerprint)
    XCTAssertEqual(provider.captures, 0)
  }

  func testCaptureKindsKeepIndependentReadiness() throws {
    let provider = Provider()
    provider.photo = .init(status: .requiresSetup, reason: "Fixture camera denied")
    let registry = try AgentNativeToolRegistry().registerAll(AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider))
    XCTAssertEqual(registry.descriptors().first { $0.id == AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture }?.availability, provider.photo)
    XCTAssertEqual(registry.descriptors().first { $0.id == AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord }?.availability.status, .available)
    provider.photo = .available
    provider.audio = .init(status: .unavailable, reason: "Fixture audio unavailable")
    registry.refreshAvailability()
    XCTAssertEqual(registry.descriptors().first { $0.id == AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord }?.availability, provider.audio)
    XCTAssertEqual(registry.descriptors().first { $0.id == AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture }?.availability.status, .available)
    XCTAssertEqual(provider.captures, 0)
  }

  func testCaptureInvocationRechecksReadinessWithoutRefresh() throws {
    try checkInvocation(initial: AgentIOSVisibleCaptureNativeToolCatalog.uncheckedAvailability)
  }

  func testInitialAvailableCannotOverrideCaptureReadiness() throws {
    try checkInvocation(initial: .available)
  }

  func testCaptureInvocationRetainsBothConsentAndPermissionRequirements() throws {
    let provider = Provider()
    for definition in AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider) {
      var calls = 0
      let registry = try AgentNativeToolRegistry().registerExecutable(.init(definition: definition, executor: { _ in
        calls += 1
        return .failure(code: "fixture_reached", message: "Synthetic executor; no capture")
      }))
      _ = registry.invoke(definition.id, input: input(definition), context: context(definition, permissions: false))
      for consent in definition.descriptor.requiredConsents.filter(\.required) {
        _ = registry.invoke(definition.id, input: input(definition), context: context(definition, excluding: consent.id))
      }
      XCTAssertEqual(calls, 0)
      _ = registry.invoke(definition.id, input: input(definition), context: context(definition))
      XCTAssertEqual(calls, 1)
    }
    XCTAssertEqual(provider.captures, 0)
  }

  private func checkInvocation(initial: AgentNativeToolAvailability) throws {
    let provider = Provider()
    for definition in AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider, initialAvailability: initial) {
      var calls = 0
      let registry = try AgentNativeToolRegistry().registerExecutable(.init(definition: definition, executor: { _ in
        calls += 1
        return .failure(code: "fixture_reached", message: "Synthetic executor; no capture")
      }))
      func invoke() { _ = registry.invoke(definition.id, input: input(definition), context: context(definition)) }
      provider.busy = true
      invoke()
      XCTAssertEqual(calls, 0)
      provider.busy = false
      invoke()
      XCTAssertEqual(calls, 1)
      provider.photo = .init(status: .requiresSetup, reason: "Fixture permission revoked")
      provider.audio = provider.photo
      invoke()
      XCTAssertEqual(calls, 1)
      provider.photo = .available
      provider.audio = .available
    }
    XCTAssertEqual(provider.captures, 0)
  }

  private func input(_ definition: AgentPhoneNativeToolDefinition) -> AgentMcpJSONObject {
    definition.id == AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord
      ? ["max_duration_seconds": .int(1)] : ["facing": .string("back")]
  }

  private func context(_ definition: AgentPhoneNativeToolDefinition, permissions: Bool = true,
                       excluding consent: String? = nil) -> AgentNativeToolInvocationContext {
    .init(invocationId: UUID().uuidString, sessionId: "fixture-session", conversationId: "fixture-conversation",
      turnId: UUID().uuidString, callerId: "fixture", idempotencyKey: UUID().uuidString,
      grantedPermissions: permissions ? Set(definition.descriptor.requiredPermissions.filter(\.required).map(\.id)) : [],
      grantedConsents: Set(definition.descriptor.requiredConsents.filter { $0.required && $0.id != consent }.map(\.id)))
  }

  private final class Provider: AgentIOSVisibleCaptureToolProviding {
    let implementationId = "fixture.capture.readiness"
    var photo = AgentNativeToolAvailability.available
    var audio = AgentNativeToolAvailability.available
    var busy = false
    var probes: [AgentIOSVisibleCaptureKind] = []
    var captures = 0
    func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability {
      probes.append(kind)
      return busy ? .init(status: .unavailable, reason: "Fixture capture busy") : (kind == .photo ? photo : audio)
    }
    private func unexpected() -> AgentIOSVisibleCaptureOutcome {
      captures += 1
      XCTFail("Readiness fixtures cannot open a camera, microphone or permission dialog")
      return .init(status: .failed, code: "fixture_unexpected", message: "Unexpected capture", retryable: false)
    }
    func capturePhoto(facing: String, invocation: AgentNativeToolInvocation) -> AgentIOSVisibleCaptureOutcome { unexpected() }
    func recordAudio(maxDurationSeconds: Int, invocation: AgentNativeToolInvocation) -> AgentIOSVisibleCaptureOutcome { unexpected() }
  }
}

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
