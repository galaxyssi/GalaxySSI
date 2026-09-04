import XCTest
@testable import GalaxySSI

@MainActor
final class AgentMediaNetworkPolicyTests: XCTestCase {
  func testUnmeteredValidatedNetworkKeepsNormalQuality() {
    let profile = AgentMediaNetworkPolicy.evaluate(AgentMediaNetworkProbe())

    XCTAssertEqual(profile.state, .normal)
    XCTAssertEqual(profile.id, "normal")
    XCTAssertEqual(profile.imageTargetBytes, 100_000)
    XCTAssertEqual(profile.audioSampleRateHz, 44_100)
    XCTAssertEqual(profile.audioBitRateBps, 96_000)
    XCTAssertFalse(profile.deferMediaUpload)
    XCTAssertTrue(profile.canUploadDeferredMedia)
  }

  func testMeteredNetworkUsesCompactMedia() {
    let profile = AgentMediaNetworkPolicy.evaluate(AgentMediaNetworkProbe(metered: true))

    XCTAssertEqual(profile.state, .constrained)
    XCTAssertEqual(profile.id, "constrained")
    XCTAssertEqual(profile.imageTargetBytes, 64 * 1024)
    XCTAssertEqual(profile.audioSampleRateHz, 16_000)
    XCTAssertEqual(profile.audioBitRateBps, 32_000)
    XCTAssertFalse(profile.deferMediaUpload)
  }

  func testCellularNetworkIsConstrainedEvenWhenUnmetered() {
    let profile = AgentMediaNetworkPolicy.evaluate(AgentMediaNetworkProbe(cellular: true))

    XCTAssertEqual(profile.state, .constrained)
  }

  func testLowKnownUplinkUsesCompactMedia() {
    let profile = AgentMediaNetworkPolicy.evaluate(AgentMediaNetworkProbe(upstreamKbps: 128))

    XCTAssertEqual(profile.state, .constrained)
  }

  func testUnknownBandwidthDoesNotInventAWeakNetwork() {
    let profile = AgentMediaNetworkPolicy.evaluate(
      AgentMediaNetworkProbe(downstreamKbps: 0, upstreamKbps: 0)
    )

    XCTAssertEqual(profile.state, .normal)
  }

  func testUnvalidatedNetworkDefersMediaUntilRecovery() {
    let profile = AgentMediaNetworkPolicy.evaluate(AgentMediaNetworkProbe(validated: false))

    XCTAssertEqual(profile.state, .offline)
    XCTAssertEqual(profile.id, "offline")
    XCTAssertEqual(profile.imageTargetBytes, 48 * 1024)
    XCTAssertEqual(profile.audioSampleRateHz, 16_000)
    XCTAssertEqual(profile.audioBitRateBps, 24_000)
    XCTAssertTrue(profile.deferMediaUpload)
    XCTAssertFalse(profile.canUploadDeferredMedia)
  }

  func testMediaNetworkModelsUseAndroidWireNames() throws {
    let encodedProfile = try JSONEncoder().encode(
      AgentMediaNetworkPolicy.profile(for: .constrained)
    )
    let encodedProbe = try JSONEncoder().encode(
      AgentMediaNetworkProbe(metered: true, cellular: true, transports: ["cellular"], downstreamKbps: 900, upstreamKbps: 256)
    )
    let profile = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedProfile) as? [String: Any])
    let probe = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedProbe) as? [String: Any])

    XCTAssertEqual(profile["state"] as? String, "CONSTRAINED")
    XCTAssertEqual(profile["id"] as? String, "constrained")
    XCTAssertEqual((profile["image_target_bytes"] as? NSNumber)?.intValue, 64 * 1024)
    XCTAssertEqual((profile["audio_sample_rate_hz"] as? NSNumber)?.intValue, 16_000)
    XCTAssertEqual((profile["audio_bit_rate_bps"] as? NSNumber)?.intValue, 32_000)
    XCTAssertEqual(profile["defer_media_upload"] as? Bool, false)
    XCTAssertEqual(probe["network_present"] as? Bool, true)
    XCTAssertEqual(probe["internet_capable"] as? Bool, true)
    XCTAssertEqual(probe["transports"] as? [String], ["cellular"])
    XCTAssertEqual((probe["downstream_kbps"] as? NSNumber)?.intValue, 900)
    XCTAssertEqual((probe["upstream_kbps"] as? NSNumber)?.intValue, 256)
  }

  func testMediaNetworkProbeDecodesLegacyPayloadWithoutTransports() throws {
    let decoded = try JSONDecoder().decode(
      AgentMediaNetworkProbe.self,
      from: Data(#"{"network_present":false,"internet_capable":false,"validated":false}"#.utf8)
    )

    XCTAssertFalse(decoded.networkPresent)
    XCTAssertFalse(decoded.internetCapable)
    XCTAssertFalse(decoded.validated)
    XCTAssertEqual(decoded.transports, [])
    XCTAssertEqual(decoded.downstreamKbps, 20_000)
    XCTAssertEqual(decoded.upstreamKbps, 5_000)
  }

  func testAttachmentDescriptorsCarryTransportProfileAndRespectImageBudget() {
    let profile = AgentMediaNetworkPolicy.profile(for: .constrained)
    let image = GalaxySSIDraftAttachment(
      id: "image-1",
      displayName: "photo.png",
      mimeType: "image/png",
      data: Data(repeating: 7, count: profile.imageTargetBytes + 1)
    )
    let note = GalaxySSIDraftAttachment(
      id: "note-1",
      displayName: "note.txt",
      mimeType: "text/plain",
      data: Data("hello".utf8)
    )

    let descriptors = GalaxySSIAttachmentPayloadBuilder.descriptors(
      for: [image, note],
      mediaProfile: profile
    )

    XCTAssertEqual(descriptors.count, 2)
    XCTAssertEqual(descriptors[0]["transport_profile"] as? String, "constrained")
    XCTAssertEqual(descriptors[0]["inline_status"] as? String, "metadata_only")
    XCTAssertNil(descriptors[0]["data_b64"])
    XCTAssertEqual(descriptors[1]["transport_profile"] as? String, "constrained")
    XCTAssertEqual(descriptors[1]["data_b64"] as? String, Data("hello".utf8).base64EncodedString())
    XCTAssertEqual(descriptors[1]["transport_lossless"] as? Bool, true)
  }

  func testOfflineMediaRequestsValidatedNetworkGateWithoutBlockingDocuments() {
    let profile = AgentMediaNetworkPolicy.profile(for: .offline)
    let audio = GalaxySSIDraftAttachment(
      displayName: "clip.m4a",
      mimeType: "audio/mp4",
      data: Data(repeating: 1, count: 1024)
    )
    let document = GalaxySSIDraftAttachment(
      displayName: "note.txt",
      mimeType: "text/plain",
      data: Data("hello".utf8)
    )
    let metadata = AgentMediaLinkPayloadPolicy.payloadMetadata(
      attachments: [audio],
      profile: profile
    )

    XCTAssertEqual(metadata["media_network_profile"] as? String, "offline")
    XCTAssertEqual(metadata["defer_media_upload"] as? Bool, true)
    XCTAssertTrue(AgentMediaLinkPayloadPolicy.requiresValidatedNetwork(
      attachments: [audio],
      profile: profile
    ))
    XCTAssertFalse(AgentMediaLinkPayloadPolicy.requiresValidatedNetwork(
      attachments: [document],
      profile: profile
    ))
    XCTAssertTrue(AgentMediaLinkPayloadPolicy.payloadMetadata(
      attachments: [document],
      profile: profile
    ).isEmpty)
  }

  func testDeferredMediaOutboxWaitsForValidatedNetworkWithoutBlockingText() throws {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 1_000)

    store.enqueue(
      messageId: "media",
      topic: "topic/up",
      wirePayload: #"{"type":"text","defer_media_upload":true}"#,
      requiresValidatedNetwork: true,
      now: now
    )
    store.enqueue(
      messageId: "text",
      topic: "topic/up",
      wirePayload: #"{"type":"text"}"#,
      now: now.addingTimeInterval(0.75)
    )

    XCTAssertEqual(
      store.pending(now: now.addingTimeInterval(1), allowValidatedNetworkMessages: false).map(\.messageId),
      ["text"]
    )
    XCTAssertEqual(
      store.pending(now: now.addingTimeInterval(1), allowValidatedNetworkMessages: true).map(\.messageId),
      ["media", "text"]
    )
    XCTAssertEqual(
      try XCTUnwrap(store.nextRetryDelay(now: now, allowValidatedNetworkMessages: false)),
      0.75,
      accuracy: 0.001
    )
    XCTAssertEqual(
      try XCTUnwrap(store.nextRetryDelay(now: now, allowValidatedNetworkMessages: true)),
      0,
      accuracy: 0.001
    )
  }

  func testPendingMediaOutboxUsesAndroidWireNameForNetworkGate() throws {
    let pending = PendingLinkMessage(
      messageId: "media",
      topic: "topic/up",
      wirePayload: #"{"type":"text","defer_media_upload":true}"#,
      status: "queued",
      attempts: 0,
      nextAttemptAt: Date(timeIntervalSince1970: 1),
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1),
      requiresValidatedNetwork: true
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(pending)) as? [String: Any]
    )

    XCTAssertEqual(object["requires_validated_network"] as? Bool, true)
    XCTAssertNil(object["requiresValidatedNetwork"])
  }

  private func makeDeliveryStore() -> GalaxySSILinkDeliveryStore {
    let suite = "AgentMediaNetworkPolicyTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSILinkDeliveryStore(defaults: defaults)
  }
}
