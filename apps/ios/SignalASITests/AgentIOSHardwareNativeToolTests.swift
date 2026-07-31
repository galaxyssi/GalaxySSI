import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentIOSDefaultHardwareProviderReadsBoundedBatteryState() {
    let output = AgentIOSDefaultHardwareStatusProvider().batteryStatus(nowMillis: 9_000)
    let allowedPluggedValues: Set<String> = ["none", "unknown"]
    let allowedStatusValues: Set<String> = ["charging", "discharging", "full", "unknown"]

    XCTAssertEqual(output["scope"], .string("app_visible_ios"))
    XCTAssertEqual(output["observed_at_epoch_ms"], .int(9_000))
    XCTAssertNotNil(output["charging"]?.boolValue)
    XCTAssertTrue(allowedPluggedValues.contains(output["plugged"]?.stringValue ?? ""), output["plugged"]?.stringValue ?? "nil")
    XCTAssertTrue(allowedStatusValues.contains(output["status"]?.stringValue ?? ""), output["status"]?.stringValue ?? "nil")
    if let percent = output["percent"]?.intValue {
      XCTAssertTrue((0...100).contains(percent), "Battery percent \(percent) must be bounded")
    } else {
      XCTAssertEqual(output["percent"], .null)
    }
  }

  func testAgentIOSDefaultHardwareProviderMapsMediaProbeToNetworkStatus() {
    let provider = AgentIOSDefaultHardwareStatusProvider(networkProbeProvider: {
      AgentMediaNetworkProbe(
        networkPresent: true,
        internetCapable: true,
        validated: true,
        metered: true,
        roaming: false,
        restricted: true,
        congested: false,
        cellular: true,
        transports: ["wifi", "cellular", "wifi", "unsupported"],
        downstreamKbps: 900,
        upstreamKbps: -1
      )
    })

    let output = provider.networkStatus(nowMillis: 10_000)

    XCTAssertEqual(output["connected"], .bool(true))
    XCTAssertEqual(output["validated"], .bool(true))
    XCTAssertEqual(output["metered"], .bool(true))
    XCTAssertEqual(output["roaming"], .bool(false))
    XCTAssertEqual(output["transports"], .array([.string("wifi"), .string("cellular")]))
    XCTAssertEqual(output["downstream_kbps"], .int(900))
    XCTAssertEqual(output["upstream_kbps"], .int(0))
    XCTAssertEqual(output["identifiers_included"], .bool(false))
    XCTAssertEqual(output["scope"], .string("app_visible_ios"))
    XCTAssertEqual(output["observed_at_epoch_ms"], .int(10_000))
  }

  func testAgentIOSHardwareNativeToolCatalogAndExecutorExposeAppVisibleStatus() throws {
    struct FakeHardwareProvider: AgentIOSHardwareStatusProviding {
      func batteryStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "percent": .int(73),
          "charging": .bool(true),
          "plugged": .string("usb"),
          "status": .string("charging"),
          "health": .string("unknown"),
          "scope": .string("app_visible_ios"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func powerStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "interactive": .bool(true),
          "low_power_mode": .bool(false),
          "thermal_state": .string("nominal"),
          "settings_changed": .bool(false),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func storageStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "scope": .string("app_private_volume"),
          "total_bytes": .int(1_000),
          "available_bytes": .int(300),
          "used_bytes": .int(700),
          "low_storage": .bool(false),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func networkStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "connected": .bool(true),
          "validated": .bool(true),
          "metered": .bool(false),
          "roaming": .bool(false),
          "transports": .array([.string("wifi")]),
          "identifiers_included": .bool(false),
          "scope": .string("app_visible_ios"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }
    }

    let ids = AgentIOSHardwareNativeToolCatalog.toolIds
    let definitions = AgentIOSHardwareNativeToolCatalog.definitions()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.hardwareExecutableDefinitions(
        executor: AgentIOSHardwareNativeToolExecutor(provider: FakeHardwareProvider(), nowMillis: { 4_200 })
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [
        AgentIOSHardwareNativeToolCatalog.hardwareStatusPermission,
        AgentIOSHardwareNativeToolCatalog.appVisibilityBoundaryPermission
      ],
      grantedConsents: [
        AgentIOSHardwareNativeToolCatalog.userVisibleHandoffConsent,
        AgentIOSHardwareNativeToolCatalog.installedAppsConsent,
        AgentIOSHardwareNativeToolCatalog.packageDetailConsent
      ]
    )

    XCTAssertEqual(ids.count, 14)
    XCTAssertEqual(Set(AgentIOSHardwareNativeToolCatalog.orderedToolIds), ids)
    XCTAssertEqual(Set(definitions.map(\.id)), ids)
    XCTAssertEqual(registry.ids(), AgentIOSHardwareNativeToolCatalog.executableToolIds)
    XCTAssertTrue(ids.contains(AgentIOSHardwareNativeToolCatalog.storageStatus))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSHardwareNativeToolCatalog.executorId)
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentHardwareNativeTools")
      XCTAssertEqual(definition.provenanceMetadata["background_capture"], "false")
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty, definition.id)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty, definition.id)
    }

    let battery = registry.invoke(AgentIOSHardwareNativeToolCatalog.batteryStatus, input: [:], context: context)
    let power = registry.invoke(AgentIOSHardwareNativeToolCatalog.powerStatus, input: [:], context: context)
    let storage = registry.invoke(AgentIOSHardwareNativeToolCatalog.storageStatus, input: [:], context: context)
    let network = registry.invoke(AgentIOSHardwareNativeToolCatalog.networkStatus, input: [:], context: context)
    let pairing = registry.invoke(AgentIOSHardwareNativeToolCatalog.bluetoothPairingHandoff, input: [:], context: context)
    let installedApps = registry.invoke(
      AgentIOSHardwareNativeToolCatalog.installedAppsList,
      input: ["query": .string("Signal"), "limit": .int(5)],
      context: context
    )
    let packageDetail = registry.invoke(
      AgentIOSHardwareNativeToolCatalog.packageDetail,
      input: ["package_name": .string("com.example.app")],
      context: context
    )
    let location = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.locationForegroundRead }
    )
    let installedAppsDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.installedAppsList }
    )

    XCTAssertTrue(battery.isSuccess)
    XCTAssertEqual(battery.output["percent"], .int(73))
    XCTAssertEqual(battery.output["observed_at_epoch_ms"], .int(4_200))
    XCTAssertTrue(power.isSuccess)
    XCTAssertEqual(power.output["thermal_state"], .string("nominal"))
    XCTAssertTrue(storage.isSuccess)
    XCTAssertEqual(storage.output["used_bytes"], .int(700))
    XCTAssertTrue(network.isSuccess)
    XCTAssertEqual(network.output["identifiers_included"], .bool(false))
    XCTAssertTrue(pairing.isSuccess)
    XCTAssertEqual(pairing.output["settings_target"], .string("bluetooth"))
    XCTAssertEqual(pairing.output["completion_untrusted"], .bool(true))
    XCTAssertTrue(installedApps.isSuccess)
    XCTAssertEqual(installedApps.output["apps"], .array([]))
    XCTAssertEqual(installedApps.output["result_count"], .int(0))
    XCTAssertEqual(installedApps.output["query"], .string("Signal"))
    XCTAssertEqual(installedApps.output["full_inventory_available"], .bool(false))
    XCTAssertEqual(installedApps.metadata["package_inventory_exposed"], .bool(false))
    XCTAssertEqual(installedApps.metadata["platform_boundary"], .string("ios_app_visibility_boundary"))
    XCTAssertTrue(packageDetail.isSuccess)
    XCTAssertEqual(packageDetail.output["package_name"], .string("com.example.app"))
    XCTAssertEqual(packageDetail.output["visible"], .bool(false))
    XCTAssertEqual(packageDetail.output["metadata_available"], .bool(false))
    XCTAssertEqual(packageDetail.output["requested_permissions"], .array([]))
    XCTAssertEqual(packageDetail.metadata["package_inventory_exposed"], .bool(false))
    XCTAssertEqual(installedAppsDefinition.descriptor.availability.status, .available)
    XCTAssertTrue(installedAppsDefinition.descriptor.availability.reason.contains("full installed-app inventory"))
    XCTAssertEqual(location.descriptor.availability.status, .unavailable)
    XCTAssertEqual(location.descriptor.risk, .high)
  }
}
