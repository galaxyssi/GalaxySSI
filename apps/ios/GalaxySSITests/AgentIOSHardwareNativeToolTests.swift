import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSDeviceMemoryPresentationBoundsAndLocalizes() {
    let snapshot = AgentIOSDeviceMemorySnapshot(
      totalBytes: 10_000,
      availableBytes: 2_000,
      lowMemory: false,
      lowMemoryThresholdBytes: 1_000,
      pressure: "normal"
    )
    let output = AgentIOSDeviceMemoryStatusPresentation.output(snapshot: snapshot, nowMillis: 9_000)

    XCTAssertEqual(output["scope"], .string("device_ram"))
    XCTAssertEqual(output["used_bytes"], .int(8_000))
    XCTAssertEqual(output["used_percent"], .int(80))
    XCTAssertEqual(output["available_memory_estimated"], .bool(true))
    XCTAssertTrue(AgentIOSDeviceMemoryStatusPresentation.message(output: output, language: "zh-Hans").contains("\u{624b}\u{673a}\u{5185}\u{5b58}"))
    XCTAssertTrue(AgentIOSDeviceMemoryStatusPresentation.message(output: output, language: "en").contains("Phone memory"))
  }

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
    final class FakeForegroundLocationProvider: AgentIOSForegroundLocationProviding {
      var calls = 0
      var lastTimeoutMillis: Int64 = 0

      func foregroundLocation(timeoutMillis: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        calls += 1
        lastTimeoutMillis = timeoutMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "latitude": .double(37.78),
            "longitude": .double(-122.42),
            "accuracy_meters": .double(12.5),
            "altitude_meters": .null,
            "bearing_degrees": .null,
            "speed_meters_per_second": .null,
            "provider": .string("core_location"),
            "fix_at_epoch_ms": .int(nowMillis - 500),
            "observed_at_epoch_ms": .int(nowMillis),
            "age_ms": .int(500),
            "source": .string("core_location"),
            "capture_mode": .string("single_foreground_fix"),
            "background_capture": .bool(false)
          ],
          message: "Single foreground location fix read",
          metadata: [
            "retained_listener": .bool(false),
            "authorization": .string("authorized_when_in_use")
          ]
        )
      }
    }

    final class FakeSensorSampleProvider: AgentIOSSensorSampleProviding {
      var calls = 0
      var lastType = ""
      var lastTimeoutMillis: Int64 = 0

      func sampleSensor(type: String, timeoutMillis: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        calls += 1
        lastType = type
        lastTimeoutMillis = timeoutMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "type": .string(type),
            "android_type": .int(1),
            "values": .array([.double(0.1), .double(0.2), .double(0.3)]),
            "accuracy": .int(3),
            "observed_at_epoch_ms": .int(nowMillis),
            "capture_mode": .string("single_foreground_sample"),
            "background_capture": .bool(false)
          ],
          message: "Single foreground sensor sample read",
          metadata: [
            "retained_listener": .bool(false),
            "framework": .string("core_motion")
          ]
        )
      }
    }

    final class FakeBluetoothDiscoveryProvider: AgentIOSBluetoothDiscoveryProviding {
      var calls = 0
      var lastTimeoutMillis: Int64 = 0
      var lastLimit = 0

      func discoverBluetooth(timeoutMillis: Int64, limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        calls += 1
        lastTimeoutMillis = timeoutMillis
        lastLimit = limit
        return AgentNativeToolExecutionResult.success(
          output: [
            "devices": .array([
              .object([
                "address": .string("E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"),
                "name": .string("Signal Beacon"),
                "bond_state": .string("unknown"),
                "device_type": .string("low_energy"),
                "identifier_scope": .string("ios_app_scoped_uuid")
              ])
            ]),
            "result_count": .int(1),
            "completed": .bool(true),
            "timed_out": .bool(false),
            "truncated": .bool(false),
            "observed_at_epoch_ms": .int(nowMillis),
            "capture_mode": .string("single_foreground_discovery"),
            "background_capture": .bool(false)
          ],
          message: "Foreground Bluetooth discovery ended",
          metadata: [
            "scan_stopped_after_call": .bool(true),
            "hardware_addresses_included": .bool(false),
            "identifier_scope": .string("ios_app_scoped_uuid")
          ]
        )
      }
    }

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

      func nfcStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "supported": .bool(true),
          "enabled": .bool(true),
          "secure_nfc_supported": .bool(false),
          "secure_nfc_enabled": .bool(false),
          "tag_capture_started": .bool(false),
          "settings_changed": .bool(false),
          "framework": .string("core_nfc"),
          "scope": .string("ios_core_nfc_status_only"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func bluetoothStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "supported": .bool(true),
          "enabled": .bool(false),
          "enabled_state": .string("unknown_without_foreground_observation"),
          "discovering": .bool(false),
          "bonded_device_count": .null,
          "device_identifiers_included": .bool(false),
          "state_observation_started": .bool(false),
          "foreground_observation_required": .bool(true),
          "framework": .string("core_bluetooth"),
          "authorization": .string("allowed_always"),
          "scope": .string("ios_corebluetooth_status_boundary"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func sensorsList(limit: Int, nowMillis: Int64) -> AgentMcpJSONObject {
        let sensors: [AgentMcpJSONObject] = [
          [
            "type": .string("accelerometer"),
            "android_type": .int(1),
            "name": .string("iOS Accelerometer"),
            "vendor": .string("Apple"),
            "version": .int(1),
            "maximum_range": .double(0),
            "resolution": .double(0),
            "power_milliamps": .double(0),
            "reporting_mode": .string("continuous"),
            "wake_up": .bool(false),
            "runtime_permission": .null
          ],
          [
            "type": .string("gyroscope"),
            "android_type": .int(4),
            "name": .string("iOS Gyroscope"),
            "vendor": .string("Apple"),
            "version": .int(1),
            "maximum_range": .double(0),
            "resolution": .double(0),
            "power_milliamps": .double(0),
            "reporting_mode": .string("continuous"),
            "wake_up": .bool(false),
            "runtime_permission": .null
          ]
        ]
        let selected = Array(sensors.prefix(max(1, min(AgentIOSHardwareNativeToolCatalog.maxSensorResults, limit))))
        return [
          "sensors": .array(selected.map { .object($0) }),
          "result_count": .int(Int64(selected.count)),
          "truncated": .bool(sensors.count > selected.count),
          "sampling_started": .bool(false),
          "framework": .string("core_motion"),
          "scope": .string("ios_coremotion_metadata"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func setFlashlight(enabled: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "requested_enabled": .bool(enabled),
            "request_accepted": .bool(true),
            "state_verified": .bool(true),
            "settings_changed": .bool(false),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Flashlight request submitted",
          metadata: [
            "camera_capture": .bool(false),
            "continuous_state_guarantee": .bool(false),
            "framework": .string("avfoundation_torch")
          ]
        )
      }
    }

    let ids = AgentIOSHardwareNativeToolCatalog.toolIds
    let definitions = AgentIOSHardwareNativeToolCatalog.definitions()
    let locationProvider = FakeForegroundLocationProvider()
    let sensorSampleProvider = FakeSensorSampleProvider()
    let bluetoothDiscoveryProvider = FakeBluetoothDiscoveryProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.hardwareExecutableDefinitions(
        executor: AgentIOSHardwareNativeToolExecutor(
          provider: FakeHardwareProvider(),
          locationProvider: locationProvider,
          sensorSampleProvider: sensorSampleProvider,
          bluetoothDiscoveryProvider: bluetoothDiscoveryProvider,
          nowMillis: { 4_200 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [
        AgentIOSHardwareNativeToolCatalog.hardwareStatusPermission,
        AgentIOSHardwareNativeToolCatalog.appVisibilityBoundaryPermission,
        AgentIOSHardwareNativeToolCatalog.sensorSamplePermission,
        "NSLocationWhenInUseUsageDescription",
        "NSCameraUsageDescription",
        "NSBluetoothAlwaysUsageDescription"
      ],
      grantedConsents: [
        AgentIOSHardwareNativeToolCatalog.foregroundLocationConsent,
        AgentIOSHardwareNativeToolCatalog.sensorSampleConsent,
        AgentIOSHardwareNativeToolCatalog.bluetoothDiscoveryConsent,
        AgentIOSHardwareNativeToolCatalog.userVisibleHandoffConsent,
        AgentIOSHardwareNativeToolCatalog.flashlightControlConsent,
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
    let location = registry.invoke(
      AgentIOSHardwareNativeToolCatalog.locationForegroundRead,
      input: ["timeout_ms": .int(2_000)],
      context: context
    )
    let sensors = registry.invoke(
      AgentIOSHardwareNativeToolCatalog.sensorsList,
      input: ["limit": .int(1)],
      context: context
    )
    let sensorSample = registry.invoke(
      AgentIOSHardwareNativeToolCatalog.sensorSample,
      input: ["type": .string("accelerometer"), "timeout_ms": .int(1_000)],
      context: context
    )
    let flashlight = registry.invoke(
      AgentIOSHardwareNativeToolCatalog.flashlightSet,
      input: ["enabled": .bool(true)],
      context: context
    )
    let bluetooth = registry.invoke(AgentIOSHardwareNativeToolCatalog.bluetoothStatus, input: [:], context: context)
    let bluetoothDiscovery = registry.invoke(
      AgentIOSHardwareNativeToolCatalog.bluetoothDiscoveryForeground,
      input: ["timeout_ms": .int(3_000), "limit": .int(2)],
      context: context
    )
    let nfc = registry.invoke(AgentIOSHardwareNativeToolCatalog.nfcStatus, input: [:], context: context)
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
    let locationDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.locationForegroundRead }
    )
    let installedAppsDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.installedAppsList }
    )
    let nfcDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.nfcStatus }
    )
    let sensorsDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.sensorsList }
    )
    let sensorSampleDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.sensorSample }
    )
    let flashlightDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.flashlightSet }
    )
    let bluetoothDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.bluetoothStatus }
    )
    let bluetoothDiscoveryDefinition = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.bluetoothDiscoveryForeground }
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
    XCTAssertTrue(location.isSuccess)
    XCTAssertEqual(locationProvider.calls, 1)
    XCTAssertEqual(locationProvider.lastTimeoutMillis, 2_000)
    XCTAssertEqual(location.output["capture_mode"], .string("single_foreground_fix"))
    XCTAssertEqual(location.output["background_capture"], .bool(false))
    XCTAssertEqual(location.output["age_ms"], .int(500))
    XCTAssertEqual(location.metadata["retained_listener"], .bool(false))
    XCTAssertTrue(sensors.isSuccess)
    XCTAssertEqual(sensors.output["result_count"], .int(1))
    XCTAssertEqual(sensors.output["truncated"], .bool(true))
    XCTAssertEqual(sensors.output["sampling_started"], .bool(false))
    XCTAssertEqual(sensors.output["scope"], .string("ios_coremotion_metadata"))
    XCTAssertTrue(sensorSample.isSuccess)
    XCTAssertEqual(sensorSampleProvider.calls, 1)
    XCTAssertEqual(sensorSampleProvider.lastType, "accelerometer")
    XCTAssertEqual(sensorSampleProvider.lastTimeoutMillis, 1_000)
    XCTAssertEqual(sensorSample.output["capture_mode"], .string("single_foreground_sample"))
    XCTAssertEqual(sensorSample.output["background_capture"], .bool(false))
    XCTAssertEqual(sensorSample.output["values"], .array([.double(0.1), .double(0.2), .double(0.3)]))
    XCTAssertEqual(sensorSample.metadata["retained_listener"], .bool(false))
    XCTAssertTrue(flashlight.isSuccess)
    XCTAssertEqual(flashlight.output["requested_enabled"], .bool(true))
    XCTAssertEqual(flashlight.output["request_accepted"], .bool(true))
    XCTAssertEqual(flashlight.output["state_verified"], .bool(true))
    XCTAssertEqual(flashlight.output["settings_changed"], .bool(false))
    XCTAssertEqual(flashlight.metadata["camera_capture"], .bool(false))
    XCTAssertEqual(flashlight.metadata["continuous_state_guarantee"], .bool(false))
    XCTAssertTrue(bluetooth.isSuccess)
    XCTAssertEqual(bluetooth.output["supported"], .bool(true))
    XCTAssertEqual(bluetooth.output["discovering"], .bool(false))
    XCTAssertEqual(bluetooth.output["bonded_device_count"], .null)
    XCTAssertEqual(bluetooth.output["device_identifiers_included"], .bool(false))
    XCTAssertEqual(bluetooth.output["state_observation_started"], .bool(false))
    XCTAssertEqual(bluetooth.output["scope"], .string("ios_corebluetooth_status_boundary"))
    XCTAssertTrue(bluetoothDiscovery.isSuccess)
    XCTAssertEqual(bluetoothDiscoveryProvider.calls, 1)
    XCTAssertEqual(bluetoothDiscoveryProvider.lastTimeoutMillis, 3_000)
    XCTAssertEqual(bluetoothDiscoveryProvider.lastLimit, 2)
    XCTAssertEqual(bluetoothDiscovery.output["result_count"], .int(1))
    XCTAssertEqual(bluetoothDiscovery.output["completed"], .bool(true))
    XCTAssertEqual(bluetoothDiscovery.output["timed_out"], .bool(false))
    XCTAssertEqual(bluetoothDiscovery.output["capture_mode"], .string("single_foreground_discovery"))
    XCTAssertEqual(bluetoothDiscovery.output["background_capture"], .bool(false))
    XCTAssertEqual(bluetoothDiscovery.metadata["hardware_addresses_included"], .bool(false))
    XCTAssertEqual(bluetoothDiscovery.metadata["identifier_scope"], .string("ios_app_scoped_uuid"))
    XCTAssertTrue(nfc.isSuccess)
    XCTAssertEqual(nfc.output["supported"], .bool(true))
    XCTAssertEqual(nfc.output["tag_capture_started"], .bool(false))
    XCTAssertEqual(nfc.output["settings_changed"], .bool(false))
    XCTAssertEqual(nfc.output["observed_at_epoch_ms"], .int(4_200))
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
    XCTAssertEqual(nfcDefinition.descriptor.availability.status, .available)
    XCTAssertTrue(nfcDefinition.descriptor.capabilities.contains("nfc.no_tag_capture"))
    XCTAssertEqual(sensorsDefinition.descriptor.availability.status, .available)
    XCTAssertTrue(sensorsDefinition.descriptor.capabilities.contains("sensors.no_sampling"))
    XCTAssertEqual(sensorSampleDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(sensorSampleDefinition.descriptor.risk, .medium)
    XCTAssertTrue(sensorSampleDefinition.descriptor.capabilities.contains("sensors.no_background_stream"))
    XCTAssertEqual(sensorSampleDefinition.descriptor.timeoutMillis, AgentIOSHardwareNativeToolCatalog.maxSensorTimeoutMillis)
    XCTAssertEqual(flashlightDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(flashlightDefinition.descriptor.idempotency, .idempotent)
    XCTAssertTrue(flashlightDefinition.descriptor.capabilities.contains("flashlight.no_camera_capture"))
    XCTAssertEqual(bluetoothDefinition.descriptor.availability.status, .available)
    XCTAssertTrue(bluetoothDefinition.descriptor.capabilities.contains("bluetooth.no_device_identifiers"))
    XCTAssertTrue(bluetoothDefinition.descriptor.capabilities.contains("bluetooth.no_discovery"))
    XCTAssertEqual(bluetoothDiscoveryDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(bluetoothDiscoveryDefinition.descriptor.risk, .high)
    XCTAssertTrue(bluetoothDiscoveryDefinition.descriptor.capabilities.contains("bluetooth.discovery.no_background_receiver"))
    XCTAssertEqual(
      bluetoothDiscoveryDefinition.descriptor.timeoutMillis,
      AgentIOSHardwareNativeToolCatalog.maxBluetoothDiscoveryMillis
    )
    XCTAssertEqual(locationDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(locationDefinition.descriptor.risk, .high)
    XCTAssertTrue(locationDefinition.descriptor.capabilities.contains("location.no_background_tracking"))
  }
}
