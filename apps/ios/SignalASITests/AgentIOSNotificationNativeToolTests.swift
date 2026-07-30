import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentIOSNotificationNativeToolCatalogAndExecutorRedactsAndRepliesHonestly() throws {
    final class FakeNotificationProvider: AgentIOSNotificationToolProviding {
      var implementationId = "fake.ios.notification"
      var replyCalls = 0
      var replyResult = AgentIOSNotificationReplyResult(
        success: true,
        message: "Reply dispatched",
        code: "notification_reply_dispatched",
        notificationPackage: "com.example.chat",
        notificationTitle: "Example"
      )

      func availability() -> AgentNativeToolAvailability { .available }

      func snapshot(limit: Int) -> AgentIOSNotificationContext {
        AgentIOSNotificationContext(
          hasAccess: true,
          items: [
            AgentIOSNotificationItem(
              key: "normal-key",
              packageName: "com.example.chat",
              title: "Build",
              textPreview: "Ready",
              category: "chat",
              postedAtMillis: 100,
              canReply: true
            ),
            AgentIOSNotificationItem(
              key: "secret-key",
              packageName: "com.example.auth",
              title: "Verification code",
              textPreview: "Code 123456",
              category: "sms",
              postedAtMillis: 90,
              canReply: true,
              sensitiveFlags: ["verification_code"]
            )
          ].prefix(limit).map { $0 },
          sensitiveFlags: ["verification_code"],
          totalCount: 2
        )
      }

      func reply(notificationKey: String, text: String) -> AgentIOSNotificationReplyResult {
        replyCalls += 1
        return replyResult
      }
    }

    let provider = FakeNotificationProvider()
    let definitions = AgentIOSNotificationNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.notificationExecutableDefinitions(
        provider: provider,
        nowMillis: { 8_000 }
      )
    )
    let listContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
      grantedConsents: [AgentIOSNotificationNativeToolCatalog.readConsent]
    )
    let replyContext = AgentNativeToolInvocationContext(
      invocationId: "reply-first",
      idempotencyKey: "reply-once",
      grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
      grantedConsents: [AgentIOSNotificationNativeToolCatalog.replyConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSNotificationNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSNotificationNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSNotificationNativeToolCatalog.executorId)
      XCTAssertEqual(definition.provenanceMetadata["sensitive_content_policy"], "redact")
      XCTAssertEqual(definition.provenanceMetadata["reply_completion_semantics"], "reply_action_dispatched_not_delivered")
      XCTAssertEqual(definition.descriptor.risk, .high)
      XCTAssertEqual(definition.descriptor.requiredPermissions.map(\.id), [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission])
    }

    let listed = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationsList,
      input: ["limit": .int(12)],
      context: listContext
    )
    let deniedReply = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("reply-key"),
        "reply_text": .string("Hello")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "reply-denied",
        idempotencyKey: "reply-denied",
        grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission]
      )
    )
    let firstReply = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("reply-key"),
        "reply_text": .string("Hello")
      ],
      context: replyContext
    )
    let replay = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("reply-key"),
        "reply_text": .string("Hello")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "reply-replay",
        idempotencyKey: "reply-once",
        grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
        grantedConsents: [AgentIOSNotificationNativeToolCatalog.replyConsent]
      )
    )
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(provider.replyCalls, 1)
    provider.replyResult = AgentIOSNotificationReplyResult(
      success: false,
      message: "The notification is no longer available",
      code: "notification_stale",
      retryable: true,
      notificationPackage: "com.example.chat"
    )
    let stale = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("stale-key"),
        "reply_text": .string("Secret reply")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "reply-stale",
        idempotencyKey: "reply-stale",
        grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
        grantedConsents: [AgentIOSNotificationNativeToolCatalog.replyConsent]
      )
    )

    XCTAssertTrue(listed.isSuccess)
    let notifications = listed.output["notifications"]?.arrayValue ?? []
    XCTAssertEqual(notifications.count, 2)
    let normal = notifications[0].objectValue ?? [:]
    let sensitive = notifications[1].objectValue ?? [:]
    XCTAssertEqual(normal["text_preview"], .string("Ready"))
    XCTAssertEqual(normal["redacted"], .bool(false))
    XCTAssertEqual(sensitive["notification_key"], .string(""))
    XCTAssertEqual(sensitive["title"], .string(""))
    XCTAssertEqual(sensitive["text_preview"], .string(""))
    XCTAssertEqual(sensitive["redacted"], .bool(true))
    XCTAssertEqual(sensitive["can_reply"], .bool(false))
    XCTAssertEqual(listed.metadata["raw_sensitive_content_exposed"], .bool(false))

    XCTAssertEqual(deniedReply.status, .rejected)
    XCTAssertEqual(deniedReply.error?.code, "missing_consents")
    XCTAssertTrue(firstReply.isSuccess)
    XCTAssertEqual(firstReply.output["dispatch_accepted"], .bool(true))
    XCTAssertEqual(firstReply.output["delivery_verified"], .bool(false))
    XCTAssertEqual(firstReply.metadata["handoff_only"], .bool(true))
    XCTAssertEqual(firstReply.metadata["reply_text_retained"], .bool(false))
    XCTAssertEqual(firstReply.output["reply_length"], .int(5))
    XCTAssertEqual(firstReply.output["notification_key_sha256"]?.stringValue?.count, 64)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(provider.replyCalls, 2)
    XCTAssertEqual(stale.status, .failed)
    XCTAssertEqual(stale.error?.code, "notification_stale")
    XCTAssertEqual(stale.error?.retryable, true)
    XCTAssertFalse(stale.toJson().contains("Secret reply"))
  }

}
