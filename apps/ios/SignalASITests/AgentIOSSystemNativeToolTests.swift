import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentIOSSystemNativeToolCatalogMirrorsAndroidSystemIdsWithIOSBoundaries() throws {
    let ids = AgentIOSSystemNativeToolCatalog.toolIds
    let definitions = AgentIOSSystemNativeToolCatalog.definitions()

    XCTAssertEqual(ids.count, 32)
    XCTAssertEqual(Set(AgentIOSSystemNativeToolCatalog.orderedToolIds), ids)
    XCTAssertEqual(Set(definitions.map(\.id)), ids)
    XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("signalasi.android.") })
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
      if AgentIOSSystemNativeToolCatalog.handoffToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("handoff request"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "handoff_request_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.calendarsList ||
          descriptor.id == AgentIOSSystemNativeToolCatalog.calendarEventsQuery {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("EventKit"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "eventkit_calendar_read_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.contactsSearch {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("Contacts"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "contacts_search_on_ios15")
      } else if AgentIOSSystemNativeToolCatalog.downloadToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("URLSession"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "url_session_download_manager_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.wifiStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("NWPath"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "nw_path_wifi_status_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.audioStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("AVAudioSession"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "av_audio_session_status_on_ios15")
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.biometricStatus {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("LocalAuthentication"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "local_authentication_status_on_ios15")
      } else {
        XCTAssertEqual(descriptor.availability.status, .unavailable)
        XCTAssertTrue(descriptor.availability.reason.contains("iOS 15+ app sandbox"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "descriptor_only_unavailable_on_ios15")
      }
      if descriptor.id == AgentIOSSystemNativeToolCatalog.audioStatus {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosAudioStatusPermission
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
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.contactsSearch {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosContactsReadPermission
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
      } else if descriptor.id == AgentIOSSystemNativeToolCatalog.biometricStatus {
        XCTAssertTrue(descriptor.requiredPermissions.contains {
          $0.id == AgentIOSSystemNativeToolCatalog.iosBiometricStatusPermission
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

    let smsSend = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.smsSend })
    XCTAssertEqual(smsSend.descriptor.risk, .high)
    XCTAssertEqual(smsSend.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertTrue(smsSend.descriptor.requiredPermissions.contains { $0.id == "android.permission.SEND_SMS" })
    XCTAssertTrue(smsSend.descriptor.requiredConsents.contains { $0.id == "signalasi.consent.sms.send" })
    XCTAssertTrue((smsSend.descriptor.inputSchema["required"]?.arrayValue ?? []).contains(.string("phone_number")))
    XCTAssertTrue((smsSend.descriptor.inputSchema["required"]?.arrayValue ?? []).contains(.string("message")))

    let downloadEnqueue = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.downloadEnqueue })
    let downloadRemove = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.downloadRemove })
    XCTAssertEqual(downloadEnqueue.descriptor.risk, .medium)
    XCTAssertEqual(downloadEnqueue.descriptor.idempotency, .nonIdempotent)
    XCTAssertTrue(downloadEnqueue.descriptor.requiredPermissions.contains {
      $0.id == AgentIOSSystemNativeToolCatalog.iosDownloadPermission
    })
    XCTAssertTrue(downloadEnqueue.descriptor.requiredConsents.contains { $0.id == "signalasi.consent.download" })
    XCTAssertEqual(downloadRemove.descriptor.risk, .high)
    XCTAssertEqual(downloadRemove.descriptor.idempotency, .idempotencyKeyRequired)

    let registry = try AgentNativeToolRegistry(definitions: definitions)
    let unavailable = registry.authorize(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: [
        "phone_number": .string("+15551234567"),
        "message": .string("hello")
      ],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "sms-1",
        grantedPermissions: [
          AgentIOSSystemNativeToolCatalog.androidSystemPermission,
          "android.permission.SEND_SMS"
        ],
        grantedConsents: ["signalasi.consent.sms.send"]
      )
    )
    let invalid = registry.validateInput(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: ["phone_number": .string("+15551234567")]
    )

    XCTAssertEqual(unavailable.code, "tool_unavailable")
    XCTAssertFalse(unavailable.allowed)
    XCTAssertFalse(invalid.isValid)
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
      grantedConsents: ["signalasi.consent.download"]
    )
    let removeContext = AgentNativeToolInvocationContext(
      idempotencyKey: "remove-download-99",
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.iosDownloadPermission],
      grantedConsents: ["signalasi.consent.download"]
    )

    let enqueued = registry.invoke(
      AgentIOSSystemNativeToolCatalog.downloadEnqueue,
      input: [
        "url": .string("https://signalasi.example/file.txt"),
        "title": .string("File"),
        "description": .string("Example")
      ],
      context: downloadContext
    )
    let invalidURL = registry.invoke(
      AgentIOSSystemNativeToolCatalog.downloadEnqueue,
      input: ["url": .string("http://signalasi.example/file.txt")],
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
    XCTAssertEqual(provider.capturedURL, "https://signalasi.example/file.txt")
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
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions()
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.androidSystemPermission]
    )

    let dial = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyDialHandoff,
      input: ["phone_number": .string("+1 (555) 123-4567")],
      context: context
    )
    let sms = registry.invoke(
      AgentIOSSystemNativeToolCatalog.smsComposeHandoff,
      input: [
        "phone_number": .string("+1-555-123-4567"),
        "message": .string("hello")
      ],
      context: context
    )
    let wifi = registry.invoke(
      AgentIOSSystemNativeToolCatalog.wifiPanelOpen,
      input: [:],
      context: context
    )
    let invalidDial = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyDialHandoff,
      input: ["phone_number": .string("call-me")],
      context: context
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

    XCTAssertTrue(wifi.isSuccess)
    XCTAssertEqual(wifi.output["handoff_kind"], .string("settings"))
    XCTAssertEqual(wifi.output["url"], .string("app-settings:"))
    XCTAssertEqual(wifi.output["settings_target"], .string("wifi"))

    XCTAssertEqual(invalidDial.status, .failed)
    XCTAssertEqual(invalidDial.error?.code, "invalid_phone_number")
  }
}
