import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSSystemNativeToolCatalogMirrorsAndroidSystemIdsWithIOSBoundaries() throws {
    let ids = AgentIOSSystemNativeToolCatalog.toolIds
    let definitions = AgentIOSSystemNativeToolCatalog.definitions()

    XCTAssertEqual(ids.count, 32)
    XCTAssertEqual(Set(AgentIOSSystemNativeToolCatalog.orderedToolIds), ids)
    XCTAssertEqual(Set(definitions.map(\.id)), ids)
    XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("galaxyssi.android.") })
    XCTAssertTrue(ids.allSatisfy { !$0.contains(" ") })
    [
      ".telephony.", ".sms.", ".contacts.", ".calendar.", ".wifi.",
      ".audio.", ".download.", ".biometric.", ".vpn.", ".device_policy."
    ].forEach { domain in
      XCTAssertTrue(ids.contains { $0.contains(domain) }, "Missing \(domain) tools")
    }

    definitions.forEach { definition in
      let descriptor = definition.descriptor
      XCTAssertEqual(definition.executorId, AgentIOSSystemNativeToolCatalog.executorId)
      XCTAssertEqual(descriptor.location, .androidSystem)
      if AgentIOSSystemNativeToolCatalog.telephonyReadToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("CoreTelephony"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "core_telephony_callkit_status_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.smsHandoffToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("Messages compose handoff"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "sms_compose_handoff_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.smsInboxBoundaryToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("SMS inbox boundary"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "ios_sms_inbox_boundary_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.handoffToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("handoff request"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "handoff_request_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.calendarsList ||
          descriptor.id == AgentIOSSystemNativeToolCatalog.calendarEventsQuery {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("EventKit"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "eventkit_calendar_read_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.calendarWriteToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("EventKit"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "eventkit_calendar_write_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.contactsSearch {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("Contacts"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "contacts_search_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.contactsWriteToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("CNSaveRequest"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "contacts_write_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.downloadToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("URLSession"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "url_session_download_manager_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.wifiStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("NWPath"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "nw_path_wifi_status_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.wifiScanBoundaryToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("Wi-Fi scan boundary"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "ios_wifi_scan_boundary_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.audioStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("AVAudioSession"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "av_audio_session_status_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.audioControlBoundaryToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("audio-control boundary"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "ios_audio_control_boundary_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.biometricStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("LocalAuthentication"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "local_authentication_status_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.vpnStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("NetworkExtension"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "network_extension_vpn_status_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.devicePolicyStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("device policy boundaries"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "ios_app_visible_device_policy_status_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.devicePolicyActionBoundaryToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("device-policy action boundary"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "ios_device_policy_action_boundary_on_ios15")
      } else {
        XCTAssertEqual(descriptor.availability.status, .unavailable)
        XCTAssertTrue(descriptor.availability.reason.contains("iOS 15+ app sandbox"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "descriptor_only_unavailable_on_ios15")
      }
      if AgentIOSSystemNativeToolCatalog.telephonyReadToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosTelephonyStatusPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.smsHandoffToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosSMSComposePermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.smsInboxBoundaryToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosSMSInboxBoundaryPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.audioStatus {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosAudioStatusPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.audioControlBoundaryToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosAudioControlBoundaryPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.calendarsList ||
          descriptor.id == AgentIOSSystemNativeToolCatalog.calendarEventsQuery {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosCalendarReadPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.calendarWriteToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosCalendarWritePermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.contactsSearch {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosContactsReadPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.contactsWriteToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosContactsWritePermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.wifiStatus {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosWifiStatusPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.wifiScanBoundaryToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosWifiScanBoundaryPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.biometricStatus {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosBiometricStatusPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.vpnStatus {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosVPNStatusPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.devicePolicyStatus {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosDevicePolicyStatusPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.devicePolicyActionBoundaryToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosDevicePolicyActionBoundaryPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else if AgentIOSSystemNativeToolCatalog.downloadToolIds.contains(descriptor.id) {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosDownloadPermission
        }, descriptor.id)
        XCTAssertFalse(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      } else {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
        }, descriptor.id)
      }
      XCTAssertTrue(descriptor.requiredConsents.contains {
        $0.id == AgentIOSSystemNativeToolCatalog.compatibilityConsent
      }, descriptor.id)
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios")
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentAndroidSystemNativeTools")
    }

    let telephonyStatus = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.telephonyStatus })
    let telephonyCallState = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.telephonyCallState })
    let telephonyObserve = try XCTUnwrap(definitions.first {
      $0.id == AgentIOSSystemNativeToolCatalog.telephonyCallStateObserve
    })
    XCTAssertEqual(telephonyStatus.descriptor.risk, .low)
    XCTAssertEqual(telephonyStatus.descriptor.availability.status, .available)
    XCTAssertTrue(telephonyStatus.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosTelephonyStatusPermission
    })
    XCTAssertFalse(telephonyStatus.descriptor.requiredPermissions.contains { $0.id == "android.permission.READ_PHONE_STATE" })
    XCTAssertEqual(telephonyCallState.descriptor.risk, .low)
    XCTAssertTrue(telephonyCallState.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosTelephonyStatusPermission
    })
    XCTAssertEqual(telephonyObserve.descriptor.availability.status, .available)
    XCTAssertTrue(telephonyObserve.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosTelephonyStatusPermission
    })
    XCTAssertTrue((telephonyObserve.descriptor.inputSchema["required"]?.arrayValue ?? []).isEmpty)

    let smsList = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.smsList })
    XCTAssertEqual(smsList.descriptor.risk, .low)
    XCTAssertEqual(smsList.descriptor.availability.status, .available)
    XCTAssertTrue(smsList.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosSMSInboxBoundaryPermission
    })
    XCTAssertFalse(smsList.descriptor.requiredPermissions.contains { $0.id == "android.permission.READ_SMS" })

    let smsSend = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.smsSend })
    XCTAssertEqual(smsSend.descriptor.risk, .high)
    XCTAssertEqual(smsSend.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(smsSend.descriptor.availability.status, .available)
    XCTAssertTrue(smsSend.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosSMSComposePermission
    })
    XCTAssertFalse(smsSend.descriptor.requiredPermissions.contains { $0.id == "android.permission.SEND_SMS" })
    XCTAssertTrue(smsSend.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.sms.send" })
    XCTAssertTrue((smsSend.descriptor.inputSchema["required"]?.arrayValue ?? []).contains(.string("phone_number")))
    XCTAssertTrue((smsSend.descriptor.inputSchema["required"]?.arrayValue ?? []).contains(.string("message")))

    let contactsUpsert = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.contactsUpsert })
    let contactsDelete = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.contactsDelete })
    XCTAssertEqual(contactsUpsert.descriptor.risk, .high)
    XCTAssertEqual(contactsUpsert.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertTrue(contactsUpsert.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosContactsWritePermission
    })
    XCTAssertTrue(contactsUpsert.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.contacts.write" })
    XCTAssertEqual(contactsDelete.descriptor.risk, .high)
    XCTAssertEqual(contactsDelete.descriptor.idempotency, .idempotencyKeyRequired)

    let calendarUpsert = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.calendarEventUpsert })
    let calendarDelete = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.calendarEventDelete })
    XCTAssertEqual(calendarUpsert.descriptor.risk, .high)
    XCTAssertEqual(calendarUpsert.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertTrue(calendarUpsert.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosCalendarWritePermission
    })
    XCTAssertTrue(calendarUpsert.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.calendar.write" })
    XCTAssertEqual(calendarDelete.descriptor.risk, .high)
    XCTAssertEqual(calendarDelete.descriptor.idempotency, .idempotencyKeyRequired)

    let downloadEnqueue = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.downloadEnqueue })
    let downloadRemove = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.downloadRemove })
    XCTAssertEqual(downloadEnqueue.descriptor.risk, .medium)
    XCTAssertEqual(downloadEnqueue.descriptor.idempotency, .nonIdempotent)
    XCTAssertTrue(downloadEnqueue.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosDownloadPermission
    })
    XCTAssertTrue(downloadEnqueue.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.download" })
    XCTAssertEqual(downloadRemove.descriptor.risk, .high)
    XCTAssertEqual(downloadRemove.descriptor.idempotency, .idempotencyKeyRequired)

    let audioVolumeSet = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.audioVolumeSet })
    let audioMuteSet = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.audioMuteSet })
    XCTAssertEqual(audioVolumeSet.descriptor.risk, .medium)
    XCTAssertEqual(audioVolumeSet.descriptor.availability.status, .available)
    XCTAssertTrue(audioVolumeSet.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosAudioControlBoundaryPermission
    })
    XCTAssertTrue(audioVolumeSet.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.audio.change" })
    XCTAssertEqual(audioMuteSet.descriptor.risk, .medium)
    XCTAssertEqual(audioMuteSet.descriptor.availability.status, .available)
    XCTAssertTrue(audioMuteSet.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosAudioControlBoundaryPermission
    })
    XCTAssertTrue(audioMuteSet.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.audio.change" })

    let vpnStatus = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.vpnStatus })
    XCTAssertEqual(vpnStatus.descriptor.risk, .low)
    XCTAssertEqual(vpnStatus.descriptor.availability.status, .available)
    XCTAssertTrue(vpnStatus.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosVPNStatusPermission
    })

    let devicePolicyStatus = try XCTUnwrap(definitions.first {
      $0.id == AgentIOSSystemNativeToolCatalog.devicePolicyStatus
    })
    XCTAssertEqual(devicePolicyStatus.descriptor.risk, .low)
    XCTAssertEqual(devicePolicyStatus.descriptor.availability.status, .available)
    XCTAssertTrue(devicePolicyStatus.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosDevicePolicyStatusPermission
    })

    let devicePolicyLock = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.devicePolicyLock })
    let devicePolicyReboot = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.devicePolicyReboot })
    XCTAssertEqual(devicePolicyLock.descriptor.risk, .high)
    XCTAssertEqual(devicePolicyLock.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(devicePolicyLock.descriptor.availability.status, .available)
    XCTAssertTrue(devicePolicyLock.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosDevicePolicyActionBoundaryPermission
    })
    XCTAssertTrue(devicePolicyLock.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.device_policy" })
    XCTAssertEqual(devicePolicyReboot.descriptor.risk, .high)
    XCTAssertEqual(devicePolicyReboot.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(devicePolicyReboot.descriptor.availability.status, .available)
    XCTAssertTrue(devicePolicyReboot.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosDevicePolicyActionBoundaryPermission
    })
    XCTAssertTrue(devicePolicyReboot.descriptor.requiredConsents.contains { $0.id == "galaxyssi.consent.device_policy" })

    let wifiScanResults = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.wifiScanResults })
    let wifiScanStart = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.wifiScanStart })
    XCTAssertEqual(wifiScanResults.descriptor.risk, .low)
    XCTAssertEqual(wifiScanResults.descriptor.availability.status, .available)
    XCTAssertTrue(wifiScanResults.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosWifiScanBoundaryPermission
    })
    XCTAssertEqual(wifiScanStart.descriptor.risk, .medium)
    XCTAssertEqual(wifiScanStart.descriptor.availability.status, .available)
    XCTAssertTrue(wifiScanStart.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosWifiScanBoundaryPermission
    })

    let registry = try AgentNativeToolRegistry(definitions: definitions)
    let authorized = registry.authorize(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: [
        "phone_number": .string("+15551234567"),
        "message": .string("hello")
      ],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "sms-1",
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosSMSComposePermission],
        grantedConsents: ["galaxyssi.consent.sms.send"]
      )
    )
    let invalid = registry.validateInput(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: ["phone_number": .string("+15551234567")]
    )

    XCTAssertTrue(authorized.allowed)
    XCTAssertFalse(invalid.isValid)
  }

  func testAgentIOSSystemNativeToolExecutorReadsTelephonyStatusAndCallState() throws {
    final class FakeTelephonyProvider: AgentIOSTelephonyStatusProviding {
      var capturedStatusNow: Int64 = 0
      var capturedCallNow: Int64 = 0
      var capturedObserveTimeout: Int64 = 0
      var capturedObserveNow: Int64 = 0

      func telephonyStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        capturedStatusNow = nowMillis
        return [
          "phone_type": .string("cellular_capable_ios"),
          "sim_state": .string("carrier_info_available"),
          "network_operator_name": .string("Example Wireless"),
          "network_country_iso": .string("us"),
          "data_state": .string("not_exposed_ios"),
          "call_state": .string("idle"),
          "data_enabled": .null,
          "carrier_count": .int(1),
          "carriers": .array([
            .object([
              "service_id": .string("0001"),
              "carrier_name": .string("Example Wireless"),
              "iso_country_code": .string("us"),
              "identifiers_included": .bool(false)
            ])
          ]),
          "radio_access_technologies": .array([
            .object([
              "service_id": .string("0001"),
              "radio_access_technology": .string("CTRadioAccessTechnologyLTE")
            ])
          ]),
          "call_state_scope": .string("app_visible_ios_callkit"),
          "identifiers_included": .bool(false),
          "scope": .string("app_visible_ios_telephony_status"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func callState(nowMillis: Int64) -> AgentMcpJSONObject {
        capturedCallNow = nowMillis
        return [
          "call_state": .string("off_hook"),
          "active_call_count": .int(1),
          "outgoing_call_count": .int(0),
          "on_hold_call_count": .int(0),
          "ringing_detection_supported": .bool(false),
          "continuous_listener_supported": .bool(false),
          "identifiers_included": .bool(false),
          "scope": .string("app_visible_ios_callkit"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func observeCallState(timeoutMillis: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedObserveTimeout = timeoutMillis
        capturedObserveNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "initial_state": .string("idle"),
            "observed_state": .string("off_hook"),
            "changed": .bool(true),
            "timed_out": .bool(false),
            "timeout_ms": .int(timeoutMillis),
            "continuous_listener_supported": .bool(true),
            "ringing_detection_supported": .bool(false),
            "active_call_count": .int(1),
            "outgoing_call_count": .int(0),
            "on_hold_call_count": .int(0),
            "identifiers_included": .bool(false),
            "scope": .string("app_visible_ios_callkit"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Call state transition observed"
        )
      }
    }
    let provider = FakeTelephonyProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          telephonyProvider: provider,
          nowMillis: { 13_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosTelephonyStatusPermission]
    )

    let status = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyStatus,
      input: [:],
      context: context
    )
    let callState = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyCallState,
      input: [:],
      context: context
    )
    let observed = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyCallStateObserve,
      input: ["timeout_ms": .int(45_000)],
      context: context
    )

    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["network_operator_name"], .string("Example Wireless"))
    XCTAssertEqual(status.output["carrier_count"], .int(1))
    XCTAssertEqual(status.output["identifiers_included"], .bool(false))
    XCTAssertEqual(status.output["observed_at_epoch_ms"], .int(13_000))
    XCTAssertEqual(provider.capturedStatusNow, 13_000)
    XCTAssertEqual(status.metadata["identifiers_included"], .bool(false))
    XCTAssertEqual(status.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)

    XCTAssertTrue(callState.isSuccess)
    XCTAssertEqual(callState.output["call_state"], .string("off_hook"))
    XCTAssertEqual(callState.output["active_call_count"], .int(1))
    XCTAssertEqual(callState.output["ringing_detection_supported"], .bool(false))
    XCTAssertEqual(callState.output["continuous_listener_supported"], .bool(false))
    XCTAssertEqual(callState.output["observed_at_epoch_ms"], .int(13_000))
    XCTAssertEqual(provider.capturedCallNow, 13_000)
    XCTAssertEqual(callState.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)

    XCTAssertTrue(observed.isSuccess)
    XCTAssertEqual(provider.capturedObserveTimeout, 30_000)
    XCTAssertEqual(provider.capturedObserveNow, 13_000)
    XCTAssertEqual(observed.output["initial_state"], .string("idle"))
    XCTAssertEqual(observed.output["observed_state"], .string("off_hook"))
    XCTAssertEqual(observed.output["changed"], .bool(true))
    XCTAssertEqual(observed.output["timed_out"], .bool(false))
    XCTAssertEqual(observed.output["timeout_ms"], .int(30_000))
    XCTAssertEqual(observed.output["identifiers_included"], .bool(false))
    XCTAssertEqual(observed.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReturnsSMSInboxBoundary() throws {
    final class FakeSMSInboxProvider: AgentIOSSMSInboxProviding {
      var capturedLimit = 0
      var capturedAddress = ""
      var capturedNow: Int64 = 0

      func listMessages(limit: Int, address: String, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedLimit = limit
        capturedAddress = address
        capturedNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "messages": .array([]),
            "count": .int(0),
            "limit": .int(Int64(limit)),
            "address_filter": .string(address),
            "sms_database_read_supported": .bool(false),
            "direct_sms_read_supported": .bool(false),
            "identifiers_included": .bool(false),
            "platform": .string("ios"),
            "scope": .string("ios_sms_inbox_unavailable_app_sandbox"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "iOS does not expose the user's SMS database to normal apps."
        )
      }
    }
    let provider = FakeSMSInboxProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          smsInboxProvider: provider,
          nowMillis: { 14_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosSMSInboxBoundaryPermission]
    )

    let result = registry.invoke(
      AgentIOSSystemNativeToolCatalog.smsList,
      input: [
        "limit": .int(100),
        "address": .string("+15551234567")
      ],
      context: context
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(provider.capturedLimit, 100)
    XCTAssertEqual(provider.capturedAddress, "+15551234567")
    XCTAssertEqual(provider.capturedNow, 14_000)
    XCTAssertEqual(result.output["messages"], .array([]))
    XCTAssertEqual(result.output["count"], .int(0))
    XCTAssertEqual(result.output["sms_database_read_supported"], .bool(false))
    XCTAssertEqual(result.output["direct_sms_read_supported"], .bool(false))
    XCTAssertEqual(result.output["identifiers_included"], .bool(false))
    XCTAssertEqual(result.output["observed_at_epoch_ms"], .int(14_000))
    XCTAssertEqual(result.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReadsAudioStatus() throws {
    struct FakeAudioProvider: AgentIOSAudioStatusProviding {
      func audioStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "ringer_mode": .string("not_exposed_ios"),
          "mode": .string("default"),
          "category": .string("playback"),
          "speakerphone_on": .bool(true),
          "microphone_muted": .null,
          "streams": .object([
            "media": .object([
              "current": .int(42),
              "max": .int(100),
              "muted": .bool(false),
              "scope": .string("app_visible_output_volume")
            ])
          ]),
          "routes": .array([.string("speaker")]),
          "output_volume_percent": .int(42),
          "scope": .string("app_visible_ios"),
          "identifiers_included": .bool(false),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }
    }
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          audioProvider: FakeAudioProvider(),
          nowMillis: { 12_345 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosAudioStatusPermission]
    )

    let result = registry.invoke(
      AgentIOSSystemNativeToolCatalog.audioStatus,
      input: [:],
      context: context
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["output_volume_percent"], .int(42))
    XCTAssertEqual(result.output["routes"], .array([.string("speaker")]))
    XCTAssertEqual(result.output["identifiers_included"], .bool(false))
    XCTAssertEqual(result.output["observed_at_epoch_ms"], .int(12_345))
    XCTAssertEqual(result.metadata["settings_changed"], .bool(false))
    XCTAssertEqual(result.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReturnsAudioControlBoundary() throws {
    final class FakeAudioControlProvider: AgentIOSAudioControlProviding {
      var capturedVolumeStream = ""
      var capturedPercent = 0
      var capturedVolumeNow: Int64 = 0
      var capturedMuteStream = ""
      var capturedMuted = false
      var capturedMuteNow: Int64 = 0

      func setVolume(stream: String, percent: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedVolumeStream = stream
        capturedPercent = percent
        capturedVolumeNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "stream": .string("music"),
            "percent": .int(Int64(percent)),
            "volume": .null,
            "max": .int(100),
            "changed": .bool(false),
            "settings_changed": .bool(false),
            "global_volume_supported": .bool(false),
            "app_visible_output_volume_read_only": .bool(true),
            "platform": .string("ios"),
            "scope": .string("ios_audio_control_unavailable_app_sandbox"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "iOS does not allow normal apps to set global stream volume."
        )
      }

      func setMute(stream: String, muted: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedMuteStream = stream
        capturedMuted = muted
        capturedMuteNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "stream": .string("ring"),
            "muted": .bool(muted),
            "changed": .bool(false),
            "settings_changed": .bool(false),
            "global_mute_supported": .bool(false),
            "platform": .string("ios"),
            "scope": .string("ios_audio_control_unavailable_app_sandbox"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "iOS does not allow normal apps to mute arbitrary global audio streams."
        )
      }
    }
    let provider = FakeAudioControlProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          audioControlProvider: provider,
          nowMillis: { 43_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosAudioControlBoundaryPermission],
      grantedConsents: ["galaxyssi.consent.audio.change"]
    )

    let volume = registry.invoke(
      AgentIOSSystemNativeToolCatalog.audioVolumeSet,
      input: [
        "stream": .string("music"),
        "percent": .int(75)
      ],
      context: context
    )
    let mute = registry.invoke(
      AgentIOSSystemNativeToolCatalog.audioMuteSet,
      input: [
        "stream": .string("ring"),
        "muted": .bool(true)
      ],
      context: context
    )

    XCTAssertTrue(volume.isSuccess)
    XCTAssertEqual(provider.capturedVolumeStream, "music")
    XCTAssertEqual(provider.capturedPercent, 75)
    XCTAssertEqual(provider.capturedVolumeNow, 43_000)
    XCTAssertEqual(volume.output["changed"], .bool(false))
    XCTAssertEqual(volume.output["settings_changed"], .bool(false))
    XCTAssertEqual(volume.output["global_volume_supported"], .bool(false))
    XCTAssertEqual(volume.output["observed_at_epoch_ms"], .int(43_000))
    XCTAssertEqual(volume.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)

    XCTAssertTrue(mute.isSuccess)
    XCTAssertEqual(provider.capturedMuteStream, "ring")
    XCTAssertEqual(provider.capturedMuted, true)
    XCTAssertEqual(provider.capturedMuteNow, 43_000)
    XCTAssertEqual(mute.output["muted"], .bool(true))
    XCTAssertEqual(mute.output["changed"], .bool(false))
    XCTAssertEqual(mute.output["global_mute_supported"], .bool(false))
    XCTAssertEqual(mute.output["observed_at_epoch_ms"], .int(43_000))
    XCTAssertEqual(mute.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReadsBiometricStatus() throws {
    struct FakeBiometricProvider: AgentIOSBiometricStatusProviding {
      func biometricStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "device_secure": .bool(true),
          "can_authenticate": .bool(true),
          "can_authenticate_code": .int(0),
          "biometry_type": .string("face_id"),
          "framework": .string("LocalAuthentication"),
          "authentication_prompted": .bool(false),
          "scope": .string("app_visible_ios"),
          "identifiers_included": .bool(false),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }
    }
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          biometricProvider: FakeBiometricProvider(),
          nowMillis: { 22_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosBiometricStatusPermission]
    )

    let result = registry.invoke(
      AgentIOSSystemNativeToolCatalog.biometricStatus,
      input: [:],
      context: context
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["device_secure"], .bool(true))
    XCTAssertEqual(result.output["can_authenticate"], .bool(true))
    XCTAssertEqual(result.output["biometry_type"], .string("face_id"))
    XCTAssertEqual(result.output["authentication_prompted"], .bool(false))
    XCTAssertEqual(result.output["observed_at_epoch_ms"], .int(22_000))
    XCTAssertEqual(result.metadata["authentication_prompted"], .bool(false))
    XCTAssertEqual(result.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReadsVPNStatus() throws {
    struct FakeVPNProvider: AgentIOSVPNStatusProviding {
      func vpnStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "active": .bool(true),
          "vpn_networks": .array([
            .object([
              "network": .string("app_managed_vpn"),
              "status": .string("connected"),
              "validated": .null,
              "internet": .null,
              "scope": .string("network_extension_connection_status")
            ])
          ]),
          "consent_granted": .null,
          "connection_status": .string("connected"),
          "configuration_scope": .string("app_managed_network_extension"),
          "global_vpn_enumeration_supported": .bool(false),
          "framework": .string("NetworkExtension"),
          "identifiers_included": .bool(false),
          "scope": .string("ios_app_managed_vpn_status"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }
    }
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          vpnProvider: FakeVPNProvider(),
          nowMillis: { 23_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosVPNStatusPermission]
    )

    let result = registry.invoke(
      AgentIOSSystemNativeToolCatalog.vpnStatus,
      input: [:],
      context: context
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["active"], .bool(true))
    XCTAssertEqual(result.output["connection_status"], .string("connected"))
    XCTAssertEqual(result.output["global_vpn_enumeration_supported"], .bool(false))
    XCTAssertEqual(result.output["identifiers_included"], .bool(false))
    XCTAssertEqual(result.output["observed_at_epoch_ms"], .int(23_000))
    XCTAssertEqual(result.metadata["identifiers_included"], .bool(false))
    XCTAssertEqual(result.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReadsDevicePolicyStatus() throws {
    struct FakeDevicePolicyProvider: AgentIOSDevicePolicyStatusProviding {
      func devicePolicyStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "admin_active": .bool(false),
          "device_owner": .bool(false),
          "profile_owner": .bool(false),
          "lock_supported": .bool(false),
          "reboot_supported": .bool(false),
          "supervised_mdm_status_available": .bool(false),
          "managed_configuration_visible": .bool(false),
          "protected_data_available": .bool(true),
          "platform_management_model": .string("ios_app_sandbox"),
          "framework": .string("UIKit"),
          "scope": .string("ios_app_visible_device_policy_status"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func lockDevice(nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.failure(
          code: "device_admin_required",
          message: "iOS normal apps cannot lock the device through Android device policy.",
          details: [
            "locked": .bool(false),
            "lock_supported": .bool(false),
            "platform": .string("ios"),
            "scope": .string("ios_device_policy_action_unavailable_app_sandbox"),
            "observed_at_epoch_ms": .int(nowMillis)
          ]
        )
      }

      func rebootDevice(nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.failure(
          code: "device_owner_required",
          message: "iOS normal apps cannot reboot the device through Android device policy.",
          details: [
            "reboot_requested": .bool(false),
            "reboot_supported": .bool(false),
            "platform": .string("ios"),
            "scope": .string("ios_device_policy_action_unavailable_app_sandbox"),
            "observed_at_epoch_ms": .int(nowMillis)
          ]
        )
      }
    }
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          devicePolicyProvider: FakeDevicePolicyProvider(),
          nowMillis: { 24_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDevicePolicyStatusPermission]
    )
    let actionContext = AgentNativeToolInvocationContext(
      idempotencyKey: "device-policy-lock-1",
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDevicePolicyActionBoundaryPermission],
      grantedConsents: ["galaxyssi.consent.device_policy"]
    )

    let result = registry.invoke(
      AgentIOSSystemNativeToolCatalog.devicePolicyStatus,
      input: [:],
      context: context
    )
    let lock = registry.invoke(
      AgentIOSSystemNativeToolCatalog.devicePolicyLock,
      input: [:],
      context: actionContext
    )
    let reboot = registry.invoke(
      AgentIOSSystemNativeToolCatalog.devicePolicyReboot,
      input: [:],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "device-policy-reboot-1",
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDevicePolicyActionBoundaryPermission],
        grantedConsents: ["galaxyssi.consent.device_policy"]
      )
    )
    let missingKey = registry.invoke(
      AgentIOSSystemNativeToolCatalog.devicePolicyLock,
      input: [:],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDevicePolicyActionBoundaryPermission],
        grantedConsents: ["galaxyssi.consent.device_policy"]
      )
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["admin_active"], .bool(false))
    XCTAssertEqual(result.output["device_owner"], .bool(false))
    XCTAssertEqual(result.output["profile_owner"], .bool(false))
    XCTAssertEqual(result.output["lock_supported"], .bool(false))
    XCTAssertEqual(result.output["reboot_supported"], .bool(false))
    XCTAssertEqual(result.output["platform_management_model"], .string("ios_app_sandbox"))
    XCTAssertEqual(result.output["observed_at_epoch_ms"], .int(24_000))
    XCTAssertEqual(result.metadata["settings_changed"], .bool(false))
    XCTAssertEqual(result.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
    XCTAssertEqual(lock.status, .failed)
    XCTAssertEqual(lock.error?.code, "device_admin_required")
    XCTAssertEqual(lock.error?.details["locked"], .bool(false))
    XCTAssertEqual(lock.error?.details["lock_supported"], .bool(false))
    XCTAssertEqual(lock.error?.details["observed_at_epoch_ms"], .int(24_000))
    XCTAssertEqual(lock.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
    XCTAssertEqual(reboot.status, .failed)
    XCTAssertEqual(reboot.error?.code, "device_owner_required")
    XCTAssertEqual(reboot.error?.details["reboot_requested"], .bool(false))
    XCTAssertEqual(reboot.error?.details["reboot_supported"], .bool(false))
    XCTAssertEqual(reboot.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
    XCTAssertEqual(missingKey.status, .rejected)
    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
  }

  func testAgentIOSSystemNativeToolExecutorReadsIdentifierFreeWifiStatus() throws {
    let provider = AgentIOSDefaultWifiStatusProvider(networkProbeProvider: {
      AgentMediaNetworkProbe(
        networkPresent: true,
        internetCapable: true,
        validated: true,
        metered: false,
        roaming: false,
        restricted: false,
        congested: false,
        cellular: false,
        transports: ["wifi"],
        downstreamKbps: 0,
        upstreamKbps: 0
      )
    })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          wifiProvider: provider,
          nowMillis: { 33_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosWifiStatusPermission]
    )

    let result = registry.invoke(
      AgentIOSSystemNativeToolCatalog.wifiStatus,
      input: [:],
      context: context
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["wifi_enabled"], .bool(true))
    XCTAssertEqual(result.output["active_wifi_transport"], .bool(true))
    XCTAssertEqual(result.output["validated"], .bool(true))
    XCTAssertEqual(result.output["ssid"], .string(""))
    XCTAssertEqual(result.output["bssid"], .string(""))
    XCTAssertEqual(result.output["identifiers_included"], .bool(false))
    XCTAssertEqual(result.output["scope"], .string("app_visible_ios_no_wifi_identifiers"))
    XCTAssertEqual(result.output["observed_at_epoch_ms"], .int(33_000))
    XCTAssertEqual(result.metadata["settings_changed"], .bool(false))
    XCTAssertEqual(result.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReturnsWifiScanBoundary() throws {
    final class FakeWifiScanProvider: AgentIOSWifiScanProviding {
      var capturedLimit = 0
      var capturedResultsNow: Int64 = 0
      var capturedStartNow: Int64 = 0

      func wifiScanResults(limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedLimit = limit
        capturedResultsNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "networks": .array([]),
            "count": .int(0),
            "limit": .int(Int64(limit)),
            "scan_supported": .bool(false),
            "scan_trigger_supported": .bool(false),
            "identifiers_included": .bool(false),
            "platform": .string("ios"),
            "scope": .string("ios_wifi_scan_unavailable_app_sandbox"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "iOS does not expose nearby Wi-Fi scan results to normal apps."
        )
      }

      func startWifiScan(nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedStartNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "accepted": .bool(false),
            "may_be_throttled": .bool(false),
            "scan_supported": .bool(false),
            "scan_trigger_supported": .bool(false),
            "platform": .string("ios"),
            "scope": .string("ios_wifi_scan_unavailable_app_sandbox"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "iOS does not allow normal apps to trigger arbitrary Wi-Fi scans."
        )
      }
    }
    let provider = FakeWifiScanProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          wifiScanProvider: provider,
          nowMillis: { 34_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosWifiScanBoundaryPermission]
    )

    let results = registry.invoke(
      AgentIOSSystemNativeToolCatalog.wifiScanResults,
      input: ["limit": .int(250)],
      context: context
    )
    let started = registry.invoke(
      AgentIOSSystemNativeToolCatalog.wifiScanStart,
      input: [:],
      context: context
    )

    XCTAssertTrue(results.isSuccess)
    XCTAssertEqual(provider.capturedLimit, 100)
    XCTAssertEqual(provider.capturedResultsNow, 34_000)
    XCTAssertEqual(results.output["count"], .int(0))
    XCTAssertEqual(results.output["scan_supported"], .bool(false))
    XCTAssertEqual(results.output["identifiers_included"], .bool(false))
    XCTAssertEqual(results.output["observed_at_epoch_ms"], .int(34_000))
    XCTAssertEqual(results.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)

    XCTAssertTrue(started.isSuccess)
    XCTAssertEqual(provider.capturedStartNow, 34_000)
    XCTAssertEqual(started.output["accepted"], .bool(false))
    XCTAssertEqual(started.output["may_be_throttled"], .bool(false))
    XCTAssertEqual(started.output["scan_supported"], .bool(false))
    XCTAssertEqual(started.output["observed_at_epoch_ms"], .int(34_000))
    XCTAssertEqual(started.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorSearchesContacts() throws {
    final class FakeContactsProvider: AgentIOSContactsSearchProviding {
      var capturedQuery = ""
      var capturedLimit = 0
      var capturedNow: Int64 = 0

      func searchContacts(query: String, limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedQuery = query
        capturedLimit = limit
        capturedNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "contacts": .array([
              .object([
                "contact_id": .int(101),
                "display_name": .string("Alice Example"),
                "phone_number": .string("+15551234567"),
                "platform": .string("ios")
              ])
            ]),
            "count": .int(1),
            "query": .string(query),
            "limit": .int(Int64(limit)),
            "authorization_status": .string("authorized"),
            "scope": .string("ios_contacts_read"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Contacts search completed"
        )
      }
    }
    let provider = FakeContactsProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          contactsProvider: provider,
          nowMillis: { 44_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosContactsReadPermission]
    )

    let result = registry.invoke(
      AgentIOSSystemNativeToolCatalog.contactsSearch,
      input: [
        "query": .string("Alice"),
        "limit": .int(2)
      ],
      context: context
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(provider.capturedQuery, "Alice")
    XCTAssertEqual(provider.capturedLimit, 2)
    XCTAssertEqual(provider.capturedNow, 44_000)
    XCTAssertEqual(result.output["count"], .int(1))
    XCTAssertEqual(result.output["contacts"]?.arrayValue?.first?.objectValue?["display_name"], .string("Alice Example"))
    XCTAssertEqual(result.output["contacts"]?.arrayValue?.first?.objectValue?["phone_number"], .string("+15551234567"))
    XCTAssertEqual(result.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorWritesContacts() throws {
    final class FakeContactsWriteProvider: AgentIOSContactsWriteProviding {
      var upsertCalls: [(contactId: Int64, displayName: String, phoneNumber: String, nowMillis: Int64)] = []
      var deleteCalls: [(contactId: Int64, nowMillis: Int64)] = []

      func upsertContact(
        contactId: Int64,
        displayName: String,
        phoneNumber: String,
        nowMillis: Int64
      ) -> AgentNativeToolExecutionResult {
        upsertCalls.append((contactId, displayName, phoneNumber, nowMillis))
        if contactId <= 0 {
          return AgentNativeToolExecutionResult.success(
            output: [
              "raw_contact_id": .int(303),
              "contact_id": .int(303),
              "display_name": .string(displayName),
              "phone_number": .string(phoneNumber),
              "created": .bool(true),
              "authorization_status": .string("authorized"),
              "scope": .string("ios_contacts_write"),
              "platform": .string("ios"),
              "observed_at_epoch_ms": .int(nowMillis)
            ],
            message: "Contact created"
          )
        }
        return AgentNativeToolExecutionResult.success(
          output: [
            "contact_id": .int(contactId),
            "display_name": .string(displayName),
            "phone_number": .string(phoneNumber),
            "updated_name_rows": .int(1),
            "updated_phone_rows": .int(1),
            "contact_found": .bool(true),
            "authorization_status": .string("authorized"),
            "scope": .string("ios_contacts_write"),
            "platform": .string("ios"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Contact updated"
        )
      }

      func deleteContact(contactId: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        deleteCalls.append((contactId, nowMillis))
        return AgentNativeToolExecutionResult.success(
          output: [
            "contact_id": .int(contactId),
            "deleted_rows": .int(1),
            "contact_found": .bool(true),
            "authorization_status": .string("authorized"),
            "scope": .string("ios_contacts_write"),
            "platform": .string("ios"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Contact delete completed"
        )
      }
    }
    let provider = FakeContactsWriteProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          contactsWriteProvider: provider,
          nowMillis: { 77_000 }
        )
      )
    )
    func context(_ key: String) -> AgentNativeToolInvocationContext {
      AgentNativeToolInvocationContext(
        idempotencyKey: key,
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosContactsWritePermission],
        grantedConsents: ["galaxyssi.consent.contacts.write"]
      )
    }

    let created = registry.invoke(
      AgentIOSSystemNativeToolCatalog.contactsUpsert,
      input: [
        "display_name": .string("Alice Example"),
        "phone_number": .string("+15551234567")
      ],
      context: context("contacts-create-1")
    )
    let updated = registry.invoke(
      AgentIOSSystemNativeToolCatalog.contactsUpsert,
      input: [
        "contact_id": .int(101),
        "display_name": .string("Alice Updated"),
        "phone_number": .string("+15557654321")
      ],
      context: context("contacts-update-1")
    )
    let missingKey = registry.invoke(
      AgentIOSSystemNativeToolCatalog.contactsUpsert,
      input: ["display_name": .string("No Key")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosContactsWritePermission],
        grantedConsents: ["galaxyssi.consent.contacts.write"]
      )
    )
    let deleted = registry.invoke(
      AgentIOSSystemNativeToolCatalog.contactsDelete,
      input: ["contact_id": .int(101)],
      context: context("contacts-delete-1")
    )

    XCTAssertTrue(created.isSuccess)
    XCTAssertEqual(created.output["created"], .bool(true))
    XCTAssertEqual(created.output["raw_contact_id"], .int(303))
    XCTAssertEqual(created.metadata["executor_id"], .string(AgentIOSSystemNativeToolCatalog.executorId))
    XCTAssertTrue(updated.isSuccess)
    XCTAssertEqual(updated.output["updated_name_rows"], .int(1))
    XCTAssertEqual(updated.output["updated_phone_rows"], .int(1))
    XCTAssertEqual(provider.upsertCalls.count, 2)
    XCTAssertEqual(provider.upsertCalls.first?.displayName, "Alice Example")
    XCTAssertEqual(provider.upsertCalls.last?.contactId, 101)
    XCTAssertEqual(provider.upsertCalls.last?.nowMillis, 77_000)
    XCTAssertEqual(missingKey.status, .rejected)
    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(deleted.isSuccess)
    XCTAssertEqual(deleted.output["deleted_rows"], .int(1))
    XCTAssertEqual(provider.deleteCalls.first?.contactId, 101)
    XCTAssertEqual(deleted.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorReadsCalendarsAndEvents() throws {
    final class FakeCalendarProvider: AgentIOSCalendarReadProviding {
      var capturedStart: Int64 = 0
      var capturedEnd: Int64 = 0
      var capturedLimit = 0
      var capturedNow: Int64 = 0

      func listCalendars(nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "calendars": .array([
              .object([
                "calendar_id": .int(7),
                "display_name": .string("Work"),
                "account_name": .string("iCloud"),
                "visible": .bool(true),
                "platform": .string("ios")
              ])
            ]),
            "count": .int(1),
            "authorization_status": .string("authorized"),
            "scope": .string("ios_calendar_read"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Calendars listed"
        )
      }

      func queryEvents(
        startEpochMillis: Int64,
        endEpochMillis: Int64,
        limit: Int,
        nowMillis: Int64
      ) -> AgentNativeToolExecutionResult {
        capturedStart = startEpochMillis
        capturedEnd = endEpochMillis
        capturedLimit = limit
        capturedNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "events": .array([
              .object([
                "event_id": .int(11),
                "title": .string("Planning"),
                "start_epoch_ms": .int(startEpochMillis),
                "end_epoch_ms": .int(endEpochMillis),
                "location": .string("Office"),
                "calendar_id": .int(7),
                "platform": .string("ios")
              ])
            ]),
            "count": .int(1),
            "start_epoch_ms": .int(startEpochMillis),
            "end_epoch_ms": .int(endEpochMillis),
            "limit": .int(Int64(limit)),
            "authorization_status": .string("authorized"),
            "scope": .string("ios_calendar_read"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Calendar events queried"
        )
      }
    }
    let provider = FakeCalendarProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          calendarProvider: provider,
          nowMillis: { 55_000 }
        )
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosCalendarReadPermission]
    )

    let calendars = registry.invoke(
      AgentIOSSystemNativeToolCatalog.calendarsList,
      input: [:],
      context: context
    )
    let events = registry.invoke(
      AgentIOSSystemNativeToolCatalog.calendarEventsQuery,
      input: [
        "start_epoch_ms": .int(1_000),
        "end_epoch_ms": .int(2_000),
        "limit": .int(3)
      ],
      context: context
    )

    XCTAssertTrue(calendars.isSuccess)
    XCTAssertEqual(calendars.output["count"], .int(1))
    XCTAssertEqual(calendars.output["calendars"]?.arrayValue?.first?.objectValue?["display_name"], .string("Work"))
    XCTAssertTrue(events.isSuccess)
    XCTAssertEqual(provider.capturedStart, 1_000)
    XCTAssertEqual(provider.capturedEnd, 2_000)
    XCTAssertEqual(provider.capturedLimit, 3)
    XCTAssertEqual(provider.capturedNow, 55_000)
    XCTAssertEqual(events.output["events"]?.arrayValue?.first?.objectValue?["title"], .string("Planning"))
    XCTAssertEqual(events.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorWritesCalendarEvents() throws {
    final class FakeCalendarWriteProvider: AgentIOSCalendarWriteProviding {
      var upsertCalls: [
        (
          eventId: Int64,
          calendarId: Int64,
          title: String,
          description: String,
          location: String,
          start: Int64,
          end: Int64,
          timezone: String,
          nowMillis: Int64
        )
      ] = []
      var deleteCalls: [(eventId: Int64, nowMillis: Int64)] = []

      func upsertEvent(
        eventId: Int64,
        calendarId: Int64,
        title: String,
        description: String,
        location: String,
        startEpochMillis: Int64,
        endEpochMillis: Int64,
        timezone: String,
        nowMillis: Int64
      ) -> AgentNativeToolExecutionResult {
        upsertCalls.append((
          eventId,
          calendarId,
          title,
          description,
          location,
          startEpochMillis,
          endEpochMillis,
          timezone,
          nowMillis
        ))
        if eventId <= 0 {
          return AgentNativeToolExecutionResult.success(
            output: [
              "event_id": .int(404),
              "calendar_id": .int(calendarId),
              "title": .string(title),
              "start_epoch_ms": .int(startEpochMillis),
              "end_epoch_ms": .int(endEpochMillis),
              "location": .string(location),
              "created": .bool(true),
              "authorization_status": .string("authorized"),
              "scope": .string("ios_calendar_write"),
              "platform": .string("ios"),
              "observed_at_epoch_ms": .int(nowMillis)
            ],
            message: "Calendar event created"
          )
        }
        return AgentNativeToolExecutionResult.success(
          output: [
            "event_id": .int(eventId),
            "calendar_id": .int(calendarId),
            "title": .string(title),
            "start_epoch_ms": .int(startEpochMillis),
            "end_epoch_ms": .int(endEpochMillis),
            "location": .string(location),
            "updated_rows": .int(1),
            "event_found": .bool(true),
            "authorization_status": .string("authorized"),
            "scope": .string("ios_calendar_write"),
            "platform": .string("ios"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Calendar event updated"
        )
      }

      func deleteEvent(eventId: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        deleteCalls.append((eventId, nowMillis))
        return AgentNativeToolExecutionResult.success(
          output: [
            "event_id": .int(eventId),
            "deleted_rows": .int(1),
            "event_found": .bool(true),
            "authorization_status": .string("authorized"),
            "scope": .string("ios_calendar_write"),
            "platform": .string("ios"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Calendar event delete completed"
        )
      }
    }
    let provider = FakeCalendarWriteProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          calendarWriteProvider: provider,
          nowMillis: { 88_000 }
        )
      )
    )
    func context(_ key: String) -> AgentNativeToolInvocationContext {
      AgentNativeToolInvocationContext(
        idempotencyKey: key,
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosCalendarWritePermission],
        grantedConsents: ["galaxyssi.consent.calendar.write"]
      )
    }

    let created = registry.invoke(
      AgentIOSSystemNativeToolCatalog.calendarEventUpsert,
      input: [
        "calendar_id": .int(7),
        "title": .string("Planning"),
        "description": .string("Roadmap"),
        "location": .string("Office"),
        "start_epoch_ms": .int(10_000),
        "end_epoch_ms": .int(20_000),
        "timezone": .string("America/Los_Angeles")
      ],
      context: context("calendar-create-1")
    )
    let updated = registry.invoke(
      AgentIOSSystemNativeToolCatalog.calendarEventUpsert,
      input: [
        "event_id": .int(11),
        "calendar_id": .int(7),
        "title": .string("Planning updated"),
        "start_epoch_ms": .int(30_000),
        "end_epoch_ms": .int(40_000)
      ],
      context: context("calendar-update-1")
    )
    let missingKey = registry.invoke(
      AgentIOSSystemNativeToolCatalog.calendarEventUpsert,
      input: [
        "calendar_id": .int(7),
        "title": .string("No Key"),
        "start_epoch_ms": .int(10_000),
        "end_epoch_ms": .int(20_000)
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosCalendarWritePermission],
        grantedConsents: ["galaxyssi.consent.calendar.write"]
      )
    )
    let deleted = registry.invoke(
      AgentIOSSystemNativeToolCatalog.calendarEventDelete,
      input: ["event_id": .int(11)],
      context: context("calendar-delete-1")
    )

    XCTAssertTrue(created.isSuccess)
    XCTAssertEqual(created.output["created"], .bool(true))
    XCTAssertEqual(created.output["event_id"], .int(404))
    XCTAssertEqual(created.metadata["executor_id"], .string(AgentIOSSystemNativeToolCatalog.executorId))
    XCTAssertTrue(updated.isSuccess)
    XCTAssertEqual(updated.output["updated_rows"], .int(1))
    XCTAssertEqual(provider.upsertCalls.count, 2)
    XCTAssertEqual(provider.upsertCalls.first?.title, "Planning")
    XCTAssertEqual(provider.upsertCalls.first?.timezone, "America/Los_Angeles")
    XCTAssertEqual(provider.upsertCalls.last?.eventId, 11)
    XCTAssertEqual(provider.upsertCalls.last?.nowMillis, 88_000)
    XCTAssertEqual(missingKey.status, .rejected)
    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(deleted.isSuccess)
    XCTAssertEqual(deleted.output["deleted_rows"], .int(1))
    XCTAssertEqual(provider.deleteCalls.first?.eventId, 11)
    XCTAssertEqual(deleted.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorManagesDownloads() throws {
    final class FakeDownloadProvider: AgentIOSDownloadManaging {
      var capturedURL = ""
      var capturedTitle = ""
      var capturedDescription = ""
      var capturedEnqueueNow: Int64 = 0
      var capturedQueryId: Int64 = 0
      var capturedRemoveId: Int64 = 0

      func enqueueDownload(
        url: String,
        title: String,
        description: String,
        nowMillis: Int64
      ) -> AgentNativeToolExecutionResult {
        capturedURL = url
        capturedTitle = title
        capturedDescription = description
        capturedEnqueueNow = nowMillis
        return AgentNativeToolExecutionResult.success(
          output: [
            "download_id": .int(99),
            "url": .string(url),
            "status": .int(2),
            "reason": .int(0),
            "bytes_downloaded": .int(0),
            "total_bytes": .int(-1),
            "local_uri": .string(""),
            "media_type": .string(""),
            "platform": .string("ios"),
            "scope": .string("ios_app_cache_download"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Download enqueued"
        )
      }

      func queryDownload(id: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedQueryId = id
        return AgentNativeToolExecutionResult.success(
          output: [
            "download_id": .int(id),
            "status": .int(8),
            "reason": .int(0),
            "bytes_downloaded": .int(12),
            "total_bytes": .int(12),
            "local_uri": .string("file:///cache/download-99.txt"),
            "media_type": .string("text/plain"),
            "platform": .string("ios"),
            "scope": .string("ios_app_cache_download"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Download status read"
        )
      }

      func removeDownload(id: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        capturedRemoveId = id
        return AgentNativeToolExecutionResult.success(
          output: [
            "download_id": .int(id),
            "removed": .int(1),
            "platform": .string("ios"),
            "scope": .string("ios_app_cache_download"),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Download remove completed"
        )
      }
    }
    let provider = FakeDownloadProvider()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(
          downloadProvider: provider,
          nowMillis: { 66_000 }
        )
      )
    )
    let downloadContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDownloadPermission],
      grantedConsents: ["galaxyssi.consent.download"]
    )
    let removeContext = AgentNativeToolInvocationContext(
      idempotencyKey: "remove-download-99",
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDownloadPermission],
      grantedConsents: ["galaxyssi.consent.download"]
    )

    let enqueued = registry.invoke(
      AgentIOSSystemNativeToolCatalog.downloadEnqueue,
      input: [
        "url": .string("https://galaxyssi.example/file.txt"),
        "title": .string("File"),
        "description": .string("Example")
      ],
      context: downloadContext
    )
    let invalidURL = registry.invoke(
      AgentIOSSystemNativeToolCatalog.downloadEnqueue,
      input: ["url": .string("http://galaxyssi.example/file.txt")],
      context: downloadContext
    )
    let queried = registry.invoke(
      AgentIOSSystemNativeToolCatalog.downloadQuery,
      input: ["download_id": .int(99)],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDownloadPermission]
      )
    )
    let missingRemoveKey = registry.invoke(
      AgentIOSSystemNativeToolCatalog.downloadRemove,
      input: ["download_id": .int(99)],
      context: downloadContext
    )
    let removed = registry.invoke(
      AgentIOSSystemNativeToolCatalog.downloadRemove,
      input: ["download_id": .int(99)],
      context: removeContext
    )

    XCTAssertTrue(enqueued.isSuccess)
    XCTAssertEqual(provider.capturedURL, "https://galaxyssi.example/file.txt")
    XCTAssertEqual(provider.capturedTitle, "File")
    XCTAssertEqual(provider.capturedDescription, "Example")
    XCTAssertEqual(provider.capturedEnqueueNow, 66_000)
    XCTAssertEqual(enqueued.output["download_id"], .int(99))
    XCTAssertEqual(enqueued.output["status"], .int(2))
    XCTAssertEqual(enqueued.metadata["executor_id"], .string(AgentIOSSystemNativeToolCatalog.executorId))

    XCTAssertEqual(invalidURL.status, .failed)
    XCTAssertEqual(invalidURL.error?.code, "invalid_download_url")
    XCTAssertTrue(queried.isSuccess)
    XCTAssertEqual(provider.capturedQueryId, 99)
    XCTAssertEqual(queried.output["local_uri"], .string("file:///cache/download-99.txt"))
    XCTAssertEqual(queried.output["media_type"], .string("text/plain"))
    XCTAssertEqual(missingRemoveKey.status, .rejected)
    XCTAssertEqual(missingRemoveKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(removed.isSuccess)
    XCTAssertEqual(provider.capturedRemoveId, 99)
    XCTAssertEqual(removed.output["removed"], .int(1))
    XCTAssertEqual(removed.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)
  }

  func testAgentIOSSystemNativeToolExecutorBuildsUserVisibleHandoffs() throws {
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions(
        executor: AgentIOSSystemNativeToolExecutor(nowMillis: { 99_000 })
      )
    )
    let systemHandoffContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.androidSystemPermission]
    )
    let smsComposeContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosSMSComposePermission]
    )
    let smsSendContext = AgentNativeToolInvocationContext(
      idempotencyKey: "sms-send-1",
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosSMSComposePermission],
      grantedConsents: ["galaxyssi.consent.sms.send"]
    )

    let dial = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyDialHandoff,
      input: ["phone_number": .string("+1 (555) 123-4567")],
      context: systemHandoffContext
    )
    let sms = registry.invoke(
      AgentIOSSystemNativeToolCatalog.smsComposeHandoff,
      input: [
        "phone_number": .string("+1-555-123-4567"),
        "message": .string("hello")
      ],
      context: smsComposeContext
    )
    let directSend = registry.invoke(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: [
        "phone_number": .string("+1-555-123-4567"),
        "message": .string("send this")
      ],
      context: smsSendContext
    )
    let missingSendKey = registry.invoke(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: [
        "phone_number": .string("+1-555-123-4567"),
        "message": .string("send this")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosSMSComposePermission],
        grantedConsents: ["galaxyssi.consent.sms.send"]
      )
    )
    let emptyDirectMessage = registry.invoke(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: [
        "phone_number": .string("+1-555-123-4567"),
        "message": .string("   ")
      ],
      context: smsSendContext
    )
    let wifi = registry.invoke(
      AgentIOSSystemNativeToolCatalog.wifiPanelOpen,
      input: [:],
      context: systemHandoffContext
    )
    let invalidDial = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyDialHandoff,
      input: ["phone_number": .string("call-me")],
      context: systemHandoffContext
    )

    XCTAssertEqual(registry.ids(), AgentIOSSystemNativeToolCatalog.executableToolIds)
    XCTAssertTrue(dial.isSuccess)
    XCTAssertEqual(dial.output["handoff_kind"], .string("dial"))
    XCTAssertEqual(dial.output["url"], .string("tel:+15551234567"))
    XCTAssertEqual(dial.output["requires_user_action"], .bool(true))
    XCTAssertEqual(dial.output["completion_untrusted"], .bool(true))
    XCTAssertEqual(dial.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)

    XCTAssertTrue(sms.isSuccess)
    XCTAssertEqual(sms.output["handoff_kind"], .string("sms_compose"))
    XCTAssertEqual(sms.output["url"], .string("sms:+15551234567"))
    XCTAssertEqual(sms.output["prefill_body"], .string("hello"))
    XCTAssertEqual(sms.output["body_in_url"], .bool(false))
    XCTAssertEqual(sms.output["handoff_transport"], .string("message_compose_controller_or_sms_url"))
    XCTAssertEqual(sms.output["requested_direct_send"], .bool(false))
    XCTAssertEqual(sms.output["direct_send_supported"], .bool(false))
    XCTAssertEqual(sms.output["submitted_to_system"], .bool(false))
    XCTAssertEqual(sms.output["observed_at_epoch_ms"], .int(99_000))

    XCTAssertTrue(directSend.isSuccess)
    XCTAssertEqual(directSend.output["handoff_kind"], .string("sms_compose"))
    XCTAssertEqual(directSend.output["url"], .string("sms:+15551234567"))
    XCTAssertEqual(directSend.output["prefill_body"], .string("send this"))
    XCTAssertEqual(directSend.output["requested_direct_send"], .bool(true))
    XCTAssertEqual(directSend.output["direct_send_supported"], .bool(false))
    XCTAssertEqual(directSend.output["requires_user_action"], .bool(true))
    XCTAssertEqual(directSend.output["completion_untrusted"], .bool(true))
    XCTAssertEqual(directSend.metadata["handoff_required"], .bool(true))
    XCTAssertEqual(missingSendKey.status, .rejected)
    XCTAssertEqual(missingSendKey.error?.code, "missing_idempotency_key")
    XCTAssertEqual(emptyDirectMessage.status, .failed)
    XCTAssertEqual(emptyDirectMessage.error?.code, "invalid_message")

    XCTAssertTrue(wifi.isSuccess)
    XCTAssertEqual(wifi.output["handoff_kind"], .string("settings"))
    XCTAssertEqual(wifi.output["url"], .string("app-settings:"))
    XCTAssertEqual(wifi.output["settings_target"], .string("wifi"))

    XCTAssertEqual(invalidDial.status, .failed)
    XCTAssertEqual(invalidDial.error?.code, "invalid_phone_number")
  }
}
