import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
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
      grantedPermissions: [AgentIOSHardwareNativeToolCatalog.hardwareStatusPermission],
      grantedConsents: [AgentIOSHardwareNativeToolCatalog.userVisibleHandoffConsent]
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
    let location = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.locationForegroundRead }
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
    XCTAssertEqual(location.descriptor.availability.status, .unavailable)
    XCTAssertEqual(location.descriptor.risk, .high)
  }
}
