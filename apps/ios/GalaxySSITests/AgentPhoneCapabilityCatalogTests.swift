import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentPhoneCapabilityCatalogCoversEveryCapabilityWithHonestBoundary() {
    let capabilities = AgentPhoneCapabilityCatalog.capabilities

    XCTAssertEqual(Set(AgentPhoneCapabilityId.allCases), Set(capabilities.map(\.id)))
    XCTAssertEqual(capabilities.count, Set(capabilities.map(\.id)).count)
    XCTAssertEqual("phone.accessibility.ui.tree", AgentPhoneCapabilityId.accessibilityUITree.wireId)
    capabilities.forEach { capability in
      XCTAssertFalse(capability.userConsent.isEmpty, "\(capability.id) must declare user-consent requirements")
      XCTAssertFalse(capability.limitation.isEmpty, "\(capability.id) must state an honest limitation")
      XCTAssertNotEqual("none", capability.limitation.lowercased())
    }
  }

  func testAgentPhoneCapabilityPolicyNeverPromotesBlockedOrPrivilegedCapabilities() {
    let permissiveObservation = AgentPhoneCapabilityObservation(
      platformSupported: true,
      implementationPresent: true,
      permissionsGranted: true,
      specialAccessGranted: true,
      userConsentGranted: true,
      configured: true
    )
    let blocked = AgentPhoneCapabilityCatalog.find(.root)
    let blockedAvailability = AgentPhoneCapabilityPolicy.resolve(blocked, observation: permissiveObservation)
    let blockedStatus = AgentPhoneCapabilityStatus(
      boundary: blocked,
      availability: blockedAvailability,
      evidence: "permissive test probe"
    )

    XCTAssertEqual(blockedAvailability, .blockedByPolicy)
    XCTAssertFalse(blockedStatus.advertisedAsReady)
    let privileged = AgentPhoneCapabilityCatalog.capabilities.filter { !$0.normalAppCanExecute }
    XCTAssertFalse(privileged.isEmpty)
    privileged.forEach { boundary in
      let availability = AgentPhoneCapabilityPolicy.resolve(boundary, observation: permissiveObservation)
      let status = AgentPhoneCapabilityStatus(boundary: boundary, availability: availability, evidence: "permissive")
      XCTAssertNotEqual(availability, .ready)
      XCTAssertFalse(status.advertisedAsReady)
    }
  }

  func testAgentPhoneCapabilityPolicyReportsRuntimeAndConfigurationGates() {
    let camera = AgentPhoneCapabilityCatalog.find(.camera)
    let location = AgentPhoneCapabilityCatalog.find(.location)
    let transcode = AgentPhoneCapabilityCatalog.find(.mediaTranscode)

    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(camera, observation: AgentPhoneCapabilityObservation(permissionsGranted: false)),
      .needsRuntimePermission
    )
    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(camera, observation: AgentPhoneCapabilityObservation()),
      .ready
    )
    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(location, observation: AgentPhoneCapabilityObservation()),
      .ready
    )
    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(transcode, observation: AgentPhoneCapabilityObservation(configured: false)),
      .needsConfiguration
    )
  }

  func testAgentPhoneCapabilityNativeCoverageUsesStableAndroidToolIds() {
    let expected: Set<AgentPhoneCapabilityId> = [
      .notificationRead,
      .notificationReply,
      .camera,
      .microphone,
      .location,
      .sensors,
      .bluetooth,
      .nfc,
      .battery,
      .deviceMemory,
      .network,
      .installedApps,
      .mediaPlayback,
      .mediaTranscode
    ]

    XCTAssertEqual(expected, Set(AgentPhoneCapabilityNativeCoverage.toolIdsByCapability.keys))
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.toolIdsByCapability.values.allSatisfy { !$0.isEmpty })
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.isImplemented(.camera))
    XCTAssertFalse(AgentPhoneCapabilityNativeCoverage.isImplemented(.root))
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.coveredToolIds.contains("galaxyssi.camera.capture.visible"))
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.coveredToolIds.contains("galaxyssi.media.ffmpeg.transcode"))
    XCTAssertEqual(
      AgentPhoneCapabilityNativeCoverage.toolIdsByCapability[.network],
      [
        "galaxyssi.hardware.network.status",
        AgentIOSSystemNativeToolCatalog.wifiStatus,
        AgentIOSSystemNativeToolCatalog.wifiScanResults
      ]
    )
    XCTAssertTrue(AgentPhoneNativeToolCatalog.toolIds.contains(AgentIOSSystemNativeToolCatalog.wifiStatus))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.toolIds.contains(AgentIOSSystemNativeToolCatalog.wifiScanResults))
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.sensors).availability, .limited)
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.bluetooth).availability, .limited)
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.nfc).availability, .limited)
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.mediaTranscode).availability, .needsConfiguration)
  }

  func testAgentPhoneCapabilityModelsUseAndroidWireNames() throws {
    let boundary = AgentPhoneCapabilityCatalog.find(.camera)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(boundary)) as? [String: Any]
    )
    let observation = AgentPhoneCapabilityObservation(
      probeSucceeded: false,
      implementationPresent: false,
      permissionsGranted: false,
      evidence: "camera unavailable"
    )
    let observationObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as? [String: Any]
    )

    XCTAssertEqual(object["id"] as? String, "CAMERA")
    XCTAssertEqual(object["execution_location"] as? String, "APP_PROCESS")
    XCTAssertEqual(object["availability"] as? String, "NEEDS_RUNTIME_PERMISSION")
    XCTAssertNotNil(object["platform_permissions"])
    XCTAssertNil(object["executionLocation"])
    XCTAssertNil(object["platformPermissions"])
    XCTAssertEqual(observationObject["probe_succeeded"] as? Bool, false)
    XCTAssertEqual(observationObject["implementation_present"] as? Bool, false)
    XCTAssertEqual(observationObject["permissions_granted"] as? Bool, false)
    XCTAssertNil(observationObject["probeSucceeded"])
  }
}
