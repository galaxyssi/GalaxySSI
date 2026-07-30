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
      } else {
        XCTAssertEqual(descriptor.availability.status, .unavailable)
        XCTAssertTrue(descriptor.availability.reason.contains("iOS 15+ app sandbox"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "descriptor_only_unavailable_on_ios15")
      }
      XCTAssertTrue(descriptor.requiredPermissions.contains {
        $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
      }, descriptor.id)
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

    XCTAssertEqual(registry.ids(), AgentIOSSystemNativeToolCatalog.handoffToolIds)
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
