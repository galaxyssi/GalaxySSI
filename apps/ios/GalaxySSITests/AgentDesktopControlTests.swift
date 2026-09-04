import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentDesktopControlAuthorizationParsesAndroidRecords() throws {
    let authorization = try XCTUnwrap(AgentDesktopControlAuthorization.parse([
      "authorization_id": .string("dca_test"),
      "app_instance_id": .string("phone_route_01"),
      "app_name": .string("GalaxySSI"),
      "app_platform": .string("ios"),
      "phone_name": .string("iPhone"),
      "app_identity_fingerprint": .string("AA:BB:CC"),
      "grant_source": .string("pairing_qr"),
      "access_profile": .string("full_desktop_executor"),
      "access_scopes": .array([.string("desktop.execute"), .string("desktop.observe")]),
      "granted_at": .int(1_000),
      "last_used_at": .int(2_000),
      "status": .string("active"),
      "allowed_tools": .array([
        .string(AgentDesktopControlAction.screenshot),
        .string(AgentDesktopControlAction.clickXY)
      ]),
      "desktop_session_id": .string("session_01"),
      "desktop_session_expires_at": .int(3_000)
    ]))
    let revoked = try XCTUnwrap(AgentDesktopControlAuthorization.parse([
      "authorization_id": .string("dca_revoked"),
      "app_instance_id": .string("phone_route_02"),
      "app_name": .string("GalaxySSI"),
      "app_platform": .string("ios"),
      "status": .string("revoked"),
      "revoked_at": .int(4_000),
      "revoke_reason": .string("revoked_by_phone")
    ]))

    XCTAssertEqual(authorization.authorizationId, "dca_test")
    XCTAssertEqual(authorization.appInstanceId, "phone_route_01")
    XCTAssertEqual(authorization.appName, "GalaxySSI")
    XCTAssertEqual(authorization.appPlatform, "ios")
    XCTAssertEqual(authorization.phoneFingerprint, "AA:BB:CC")
    XCTAssertEqual(authorization.accessProfile, "full_desktop_executor")
    XCTAssertEqual(authorization.accessScopes, ["desktop.execute", "desktop.observe"])
    XCTAssertEqual(authorization.allowedTools, [AgentDesktopControlAction.screenshot, AgentDesktopControlAction.clickXY])
    XCTAssertEqual(authorization.desktopSessionId, "session_01")
    XCTAssertEqual(revoked.status, "revoked")
    XCTAssertEqual(revoked.revokedAt, 4_000)
    XCTAssertEqual(revoked.desktopSessionId, "")
    XCTAssertNil(AgentDesktopControlAuthorization.parse(["status": .string("active")]))
    XCTAssertNotNil(AgentDesktopControlAuthorization.parse(["status": .string("pending")]))
  }

  func testAgentDesktopSurfaceCatalogParsesDisplaysWindowsAndIndependentSelection() throws {
    let catalog = try XCTUnwrap(AgentDesktopSurfaceCatalog.parse([
      "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
      "displays": .array([
        .object([
          "display_id": .string("display:primary"),
          "name": .string("Display 1"),
          "primary": .bool(true),
          "bounds": .object([
            "left": .int(0),
            "top": .int(0),
            "width": .int(1_920),
            "height": .int(1_080)
          ])
        ]),
        .object([
          "display_id": .string("display:left"),
          "name": .string("Display 2"),
          "bounds": .object([
            "left": .int(-1_280),
            "top": .int(40),
            "width": .int(1_280),
            "height": .int(1_024)
          ])
        ])
      ]),
      "windows": .array([
        .object([
          "window_id": .string("window:browser"),
          "title": .string("Browser"),
          "display_id": .string("display:left"),
          "foreground": .bool(true),
          "minimized": .bool(false),
          "bounds": .object([
            "left": .int(-1_200),
            "top": .int(100),
            "width": .int(1_000),
            "height": .int(760)
          ])
        ]),
        .object([
          "window_id": .string("window:orphan"),
          "title": .string("Orphan"),
          "display_id": .string("display:missing")
        ])
      ]),
      "selection": .object([
        "selected_display_id": .string("display:left"),
        "selected_window_id": .string("window:browser"),
        "target_kind": .string("window")
      ]),
      "target": .object([
        "title": .string("Browser"),
        "bounds": .object([
          "left": .int(-1_200),
          "top": .int(100),
          "width": .int(1_000),
          "height": .int(760)
        ])
      ])
    ]))
    let nested = try XCTUnwrap(AgentDesktopSurfaceCatalog.parseOutput([
      "surface_catalog": .object([
        "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
        "displays": .array([
          .object([
            "display_id": .string("display:primary"),
            "name": .string("Display 1"),
            "bounds": .object(["width": .int(1), "height": .int(1)])
          ])
        ])
      ])
    ]))

    func request(toolId: String, input: AgentMcpJSONObject) -> AgentMcpJSONObject {
      [
        "type": .string("desktop_executor_request"),
        "task_id": .string("desktop-control-action"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string("session-1"),
        "tool_id": .string(toolId),
        "input": .object(input),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ]
    }
    let displaySelect = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.surfaceSelect, input: ["display_id": .string("display:left")]),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )
    let windowSelect = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.surfaceSelect, input: ["window_id": .string("window:browser")]),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )
    let windowActivate = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.windowActivate, input: ["window_id": .string("window:browser")]),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )

    XCTAssertEqual(catalog.displays.count, 2)
    XCTAssertEqual(catalog.windows.count, 1)
    XCTAssertEqual(catalog.selection.displayId, "display:left")
    XCTAssertEqual(catalog.selection.windowId, "window:browser")
    XCTAssertEqual(catalog.selection.targetKind, "window")
    XCTAssertEqual(catalog.targetTitle, "Browser")
    XCTAssertEqual(catalog.targetBounds.left, -1_200)
    XCTAssertTrue(catalog.displays.first?.primary == true)
    XCTAssertTrue(catalog.windows.first?.foreground == true)
    XCTAssertEqual(nested.displays.count, 1)
    XCTAssertNil(AgentDesktopSurfaceCatalog.parse([:]))
    XCTAssertNil(AgentDesktopSurfaceCatalog.parse([
      "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
      "displays": .array([])
    ]))
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.surfaceList))
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.surfaceSelect))
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.windowActivate))
    XCTAssertNotEqual(displaySelect.inputSha256, windowSelect.inputSha256)
    XCTAssertNotEqual(windowSelect.requestSha256, windowActivate.requestSha256)
  }

  func testAgentDesktopRemoteControlSnapshotCombinesAndroidState() throws {
    let screenshotBytes = Data([0xff, 0xd8, 0xff, 0xd9])
    let snapshot = try XCTUnwrap(AgentDesktopRemoteControlSnapshot.parse([
      "desktop_id": .string("desktop-1"),
      "desktop_name": .string("Workstation"),
      "desktop_fingerprint": .string("desktop-fingerprint"),
      "server_route_id": .string("server-route-1"),
      "full_desktop_executor": .bool(true),
      "enabled": .bool(true),
      "require_unlocked": .bool(true),
      "authorizations": .array([
        .object([
          "status": .string("pending")
        ]),
        .object([
          "authorization_id": .string("auth-active"),
          "status": .string("active"),
          "desktop_session_id": .string("session-1"),
          "desktop_session_expires_at": .int(1_800_000_030_000)
        ])
      ]),
      "recent_audit": .array([
        .object([
          "event_type": .string("desktop_control_action"),
          "tool_id": .string(AgentDesktopControlAction.screenshot),
          "status": .string("succeeded"),
          "summary": .string("Captured screen"),
          "created_at": .int(1_800_000_000_100)
        ])
      ]),
      "recent_receipts": .array([
        .object([
          "receipt_id": .string("receipt-1"),
          "tool_id": .string(AgentDesktopControlAction.screenshot),
          "status": .string("succeeded"),
          "summary": .string("Captured screen")
        ])
      ]),
      "active_runs": .array([
        .object([
          "task_id": .string("task-1"),
          "conversation_id": .string("conversation-1"),
          "turn_id": .string("turn-1"),
          "agent_id": .string("agent-1"),
          "status": .string("running"),
          "prompt": .string("Review desktop"),
          "current_step": .string("observing"),
          "updated_at": .int(1_800_000_000_200),
          "execution_view": .object([
            "pausable": .bool(true),
            "takeover_available": .bool(true)
          ])
        ])
      ]),
      "last_action_status": .string("succeeded"),
      "last_action_summary": .string("Captured screen"),
      "last_action_at": .int(1_800_000_000_300),
      "screenshot": .object([
        "image_mime": .string("image/jpeg"),
        "image_base64": .string(screenshotBytes.base64EncodedString()),
        "bytes": .int(Int64(screenshotBytes.count)),
        "width": .int(640),
        "height": .int(360),
        "original_width": .int(1_920),
        "original_height": .int(1_080)
      ]),
      "perception": .object([
        "contract_version": .string(AgentDesktopPerceptionSnapshot.contractVersion),
        "capture_id": .string("capture-1"),
        "captured_at": .int(1_800_000_000_400),
        "untrusted_evidence": .bool(true),
        "available_layers": .array([.string("screenshot"), .string("ui_tree")]),
        "ui_tree": .object([
          "status": .string("ok"),
          "element_count": .int(0),
          "elements": .array([])
        ])
      ]),
      "surface_catalog": .object([
        "surface_contract": .string(AgentDesktopSurfaceCatalog.contractVersion),
        "displays": .array([
          .object([
            "display_id": .string("display:primary"),
            "name": .string("Display 1"),
            "primary": .bool(true),
            "bounds": .object(["width": .int(1_920), "height": .int(1_080)])
          ])
        ]),
        "selection": .object([
          "selected_display_id": .string("display:primary"),
          "target_kind": .string("display")
        ]),
        "target": .object([
          "title": .string("Display 1"),
          "bounds": .object(["width": .int(1_920), "height": .int(1_080)])
        ])
      ]),
      "stream_fps": .int(3),
      "stream_active": .bool(true)
    ]))
    let pending = try XCTUnwrap(AgentDesktopRemoteControlSnapshot.parse([
      "full_desktop_executor": .bool(true),
      "current_authorization": .object([
        "status": .string("pending")
      ]),
      "stream_fps": .int(4)
    ]))

    XCTAssertEqual(snapshot.desktopId, "desktop-1")
    XCTAssertEqual(snapshot.desktopName, "Workstation")
    XCTAssertEqual(snapshot.currentAuthorization?.authorizationId, "auth-active")
    XCTAssertEqual(snapshot.authorizations.count, 2)
    XCTAssertTrue(snapshot.authorized)
    XCTAssertFalse(snapshot.pending)
    XCTAssertTrue(snapshot.requireUnlocked)
    XCTAssertEqual(snapshot.recentAudit.first?.summary, "Captured screen")
    XCTAssertEqual(snapshot.recentReceipts.first?.receiptId, "receipt-1")
    XCTAssertEqual(snapshot.activeRuns.first?.taskId, "task-1")
    XCTAssertEqual(snapshot.screenshot?.capturedAt, 1_800_000_000_300)
    XCTAssertEqual(snapshot.perception?.captureId, "capture-1")
    XCTAssertEqual(snapshot.surfaceCatalog?.selection.displayId, "display:primary")
    XCTAssertEqual(snapshot.streamFps, 3)
    XCTAssertTrue(snapshot.streamActive)
    XCTAssertEqual(pending.desktopName, "GalaxySSI Desktop")
    XCTAssertTrue(pending.pending)
    XCTAssertFalse(pending.authorized)
    XCTAssertEqual(pending.streamFps, 0)
    XCTAssertNil(AgentDesktopRemoteControlSnapshot.parse(nil))
  }

  func testAgentDesktopControlRequestFactoryBuildsAndroidExecutorPayloads() throws {
    let now: Int64 = 1_800_000_000_000
    let routing = AgentDesktopControlRequestRoutingContext(
      clientRouteId: "client-route-1",
      controllerFingerprint: "Controller-Fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )
    func snapshot(status: String = "active", expiresAt: Int64 = now + 60_000) throws -> AgentDesktopRemoteControlSnapshot {
      try XCTUnwrap(AgentDesktopRemoteControlSnapshot.parse([
        "desktop_id": .string("desktop-1"),
        "current_authorization": .object([
          "authorization_id": .string("auth-1"),
          "status": .string(status),
          "desktop_session_id": .string("session-1"),
          "desktop_session_expires_at": .int(expiresAt)
        ])
      ]))
    }

    let active = try snapshot()
    let screenshot = try XCTUnwrap(AgentDesktopControlRequestFactory.screenshot(
      snapshot: active,
      routing: routing,
      actionId: "action-screenshot",
      nowMillis: now
    ))
    let perception = try XCTUnwrap(AgentDesktopControlRequestFactory.perception(
      snapshot: active,
      routing: routing,
      actionId: "action-perceive",
      nowMillis: now
    ))
    let stream = try XCTUnwrap(AgentDesktopControlRequestFactory.screenshotStreamFrame(
      snapshot: active,
      routing: routing,
      fps: 2,
      actionId: "action-stream",
      nowMillis: now
    ))
    let displaySelect = try XCTUnwrap(AgentDesktopControlRequestFactory.selectDisplay(
      snapshot: active,
      routing: routing,
      displayId: "display:primary",
      actionId: "action-display",
      nowMillis: now
    ))
    let windowActivate = try XCTUnwrap(AgentDesktopControlRequestFactory.activateWindow(
      snapshot: active,
      routing: routing,
      windowId: "window:browser",
      actionId: "action-window",
      nowMillis: now
    ))
    let click = try XCTUnwrap(AgentDesktopControlRequestFactory.click(
      snapshot: active,
      routing: routing,
      x: 12,
      y: 34,
      coordinateWidth: 640,
      coordinateHeight: 360,
      actionId: "action-click",
      nowMillis: now
    ))
    let takeover = try XCTUnwrap(AgentDesktopControlRequestFactory.takeOverTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      leaseSeconds: 9_000,
      actionId: "action-takeover",
      nowMillis: now
    ))

    XCTAssertEqual(AgentDesktopControlRequestFactory.actionTTLMillis, 30_000)
    XCTAssertEqual(screenshot.payload["type"], .string("desktop_executor_request"))
    XCTAssertEqual(screenshot.payload["task_id"], .string("desktop-control-action-screenshot"))
    XCTAssertEqual(screenshot.payload["action_id"], .string("action-screenshot"))
    XCTAssertEqual(screenshot.payload["authorization_id"], .string("auth-1"))
    XCTAssertEqual(screenshot.payload["desktop_session_id"], .string("session-1"))
    XCTAssertEqual(screenshot.payload["tool_id"], .string(AgentDesktopControlAction.screenshot))
    XCTAssertEqual(screenshot.payload["input"], .object([:]))
    XCTAssertEqual(screenshot.payload["sent_at"], .int(now))
    XCTAssertEqual(screenshot.payload["expires_at"], .int(now + 30_000))
    XCTAssertEqual(screenshot.pendingRequest.desktopId, "desktop-1")
    XCTAssertEqual(screenshot.pendingRequest.toolId, AgentDesktopControlAction.screenshot)
    XCTAssertEqual(screenshot.pendingRequest.expiresAt, now + 30_000)
    XCTAssertTrue(screenshot.durable)
    XCTAssertTrue(screenshot.updatesRuntimeStatus)

    XCTAssertFalse(perception.durable)
    XCTAssertEqual(perception.input["include_screenshot"], .bool(true))
    XCTAssertEqual(perception.input["include_ocr"], .bool(true))
    XCTAssertEqual(perception.input["include_ui_tree"], .bool(true))
    XCTAssertEqual(perception.input["max_elements"], .int(80))
    XCTAssertEqual(perception.input["max_depth"], .int(8))
    XCTAssertEqual(perception.input["max_ocr_chars"], .int(12_000))
    XCTAssertFalse(stream.durable)
    XCTAssertFalse(stream.updatesRuntimeStatus)
    XCTAssertTrue(stream.pendingRequest.streamFrame)
    XCTAssertEqual(stream.input["stream_fps"], .int(2))
    XCTAssertFalse(displaySelect.durable)
    XCTAssertTrue(displaySelect.resetsSurfaceState)
    XCTAssertEqual(displaySelect.input["display_id"], .string("display:primary"))
    XCTAssertTrue(windowActivate.durable)
    XCTAssertTrue(windowActivate.resetsSurfaceState)
    XCTAssertEqual(windowActivate.input["window_id"], .string("window:browser"))
    XCTAssertEqual(click.input["button"], .string("left"))
    XCTAssertEqual(click.input["coordinate_width"], .int(640))
    XCTAssertEqual(click.input["coordinate_height"], .int(360))
    XCTAssertEqual(takeover.input["task_id"], .string("task-1"))
    XCTAssertEqual(takeover.input["lease_seconds"], .int(3_600))
    XCTAssertNotEqual(screenshot.pendingRequest.requestSha256, perception.pendingRequest.requestSha256)

    XCTAssertEqual(AgentDesktopControlRequestFactory.hotkey(
      snapshot: active,
      routing: routing,
      keys: ["ctrl", "tab"],
      actionId: "action-hotkey",
      nowMillis: now
    )?.input["keys"], .array([.string("ctrl"), .string("tab")]))
    XCTAssertEqual(AgentDesktopControlRequestFactory.windowSwitch(
      snapshot: active,
      routing: routing,
      previous: true,
      actionId: "action-window-switch",
      nowMillis: now
    )?.input["direction"], .string("previous"))
    XCTAssertEqual(AgentDesktopControlRequestFactory.selectFile(
      snapshot: active,
      routing: routing,
      path: "C:\\Users\\agent\\Desktop\\report.txt",
      actionId: "action-file",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.fileSelect)
    XCTAssertEqual(AgentDesktopControlRequestFactory.pauseTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      actionId: "action-pause",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.taskPause)
    XCTAssertEqual(AgentDesktopControlRequestFactory.continueTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      actionId: "action-continue",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.taskContinue)
    XCTAssertEqual(AgentDesktopControlRequestFactory.releaseTask(
      snapshot: active,
      routing: routing,
      taskId: "task-1",
      actionId: "action-release",
      nowMillis: now
    )?.toolId, AgentDesktopControlAction.taskRelease)
    XCTAssertNil(AgentDesktopControlRequestFactory.screenshotStreamFrame(
      snapshot: active,
      routing: routing,
      fps: 4,
      actionId: "action-bad-stream",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.typeText(
      snapshot: active,
      routing: routing,
      text: " ",
      actionId: "action-empty-type",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.typeText(
      snapshot: active,
      routing: routing,
      text: String(repeating: "x", count: 4_097),
      actionId: "action-long-type",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.hotkey(
      snapshot: active,
      routing: routing,
      keys: ["a", "b", "c", "d", "e"],
      actionId: "action-many-keys",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.scroll(
      snapshot: active,
      routing: routing,
      delta: 2_401,
      actionId: "action-scroll",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.selectDisplay(
      snapshot: active,
      routing: routing,
      displayId: "",
      actionId: "action-empty-display",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.screenshot(
      snapshot: try snapshot(status: "pending"),
      routing: routing,
      actionId: "action-pending",
      nowMillis: now
    ))
    XCTAssertNil(AgentDesktopControlRequestFactory.screenshot(
      snapshot: try snapshot(expiresAt: now),
      routing: routing,
      actionId: "action-expired",
      nowMillis: now
    ))
  }

  func testAgentDesktopControlReceiptProtocolVerifiesSignedScreenshotEvidence() throws {
    let signerId = "desktop_test"
    let desktopSessionId = "sth_desktops_00000000000000000000000000000000"
    let signatureKeyId = AgentDesktopControlReceiptProtocol.digest(Data("desktop-key".utf8))
    let controllerFingerprint = AgentDesktopControlReceiptProtocol.digest(Data("phone-key".utf8))
    let secret = Data("receipt-secret".utf8)

    func request(input: AgentMcpJSONObject = [:]) -> AgentMcpJSONObject {
      [
        "type": .string("desktop_executor_request"),
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "tool_id": .string(AgentDesktopControlAction.screenshot),
        "input": .object(input),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ]
    }

    func signedDigest(_ payload: Data) -> String {
      var data = secret
      data.append(payload)
      return AgentDesktopControlReceiptProtocol.digest(data)
    }

    func makeReceipt(
      for request: AgentMcpJSONObject,
      pending: AgentDesktopControlPendingRequest,
      screenshotBytes: Data = Data([0xff, 0xd8, 0xff, 0xd9]),
      declaredBytes: Int? = nil
    ) -> AgentMcpJSONObject {
      let evidenceSha256 = AgentDesktopControlReceiptProtocol.digest(screenshotBytes)
      let summary = "Executed desktop screenshot"
      let screenshot: AgentMcpJSONObject = [
        "image_mime": .string("image/jpeg"),
        "image_base64": .string(screenshotBytes.base64EncodedString()),
        "bytes": .int(Int64(declaredBytes ?? screenshotBytes.count)),
        "width": .int(480),
        "height": .int(270),
        "original_width": .int(1_920),
        "original_height": .int(1_080),
        "captured_at": .int(1_800_000_001_000)
      ]
      var screenshotMetadata = screenshot
      screenshotMetadata.removeValue(forKey: "image_base64")
      screenshotMetadata["image_sha256"] = .string(evidenceSha256)
      let outputSha256 = AgentDesktopControlReceiptProtocol.digest([
        "status": .string("succeeded"),
        "summary": .string(summary),
        "error": .null,
        "output": .object(["screenshot": .object(screenshotMetadata)]),
        "post_screenshot": .null
      ])
      let completedAt: Int64 = 1_800_000_001_000
      let receiptId = AgentDesktopControlReceiptProtocol.digest([
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "request_sha256": .string(pending.requestSha256),
        "output_sha256": .string(outputSha256),
        "evidence_sha256": .string(evidenceSha256),
        "completed_at": .int(completedAt)
      ])
      var receipt: AgentMcpJSONObject = [
        "type": .string("desktop_action_receipt"),
        "receipt_version": .int(Int64(AgentDesktopControlReceiptProtocol.receiptVersion)),
        "receipt_id": .string(receiptId),
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "tool_id": .string(request["tool_id"]?.stringValue ?? ""),
        "status": .string("succeeded"),
        "summary": .string(summary),
        "error_code": .string(""),
        "error_retryable": .bool(false),
        "request_sha256": .string(pending.requestSha256),
        "input_sha256": .string(pending.inputSha256),
        "output_sha256": .string(outputSha256),
        "evidence_sha256": .string(evidenceSha256),
        "controller_app_instance_id": .string("galaxyssi:phone"),
        "controller_name": .string("Test iPhone"),
        "controller_platform": .string("ios"),
        "controller_fingerprint": .string(controllerFingerprint),
        "started_at": .int(1_800_000_000_500),
        "completed_at": .int(completedAt),
        "duration_ms": .int(500),
        "signer_id": .string(signerId),
        "signature_key_id": .string(signatureKeyId),
        "output": .object(["screenshot": .object(screenshot)]),
        "post_screenshot": .null
      ]
      let signedFields: AgentMcpJSONObject = [
        "receipt_version": .int(Int64(AgentDesktopControlReceiptProtocol.receiptVersion)),
        "receipt_id": .string(receiptId),
        "task_id": .string("task-1"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string(desktopSessionId),
        "tool_id": .string(request["tool_id"]?.stringValue ?? ""),
        "status": .string("succeeded"),
        "summary": .string(summary),
        "error_code": .string(""),
        "error_retryable": .bool(false),
        "request_sha256": .string(pending.requestSha256),
        "input_sha256": .string(pending.inputSha256),
        "output_sha256": .string(outputSha256),
        "evidence_sha256": .string(evidenceSha256),
        "controller_app_instance_id": .string("galaxyssi:phone"),
        "controller_name": .string("Test iPhone"),
        "controller_platform": .string("ios"),
        "controller_fingerprint": .string(controllerFingerprint),
        "started_at": .int(1_800_000_000_500),
        "completed_at": .int(completedAt),
        "duration_ms": .int(500),
        "signer_id": .string(signerId),
        "signature_key_id": .string(signatureKeyId)
      ]
      receipt["signature"] = .string(signedDigest(Data(AgentMcpJSONCodec.stringify(signedFields).utf8)))
      return receipt
    }

    let baseRequest = request()
    let pending = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: baseRequest,
      clientRouteId: "client-route-1",
      controllerFingerprint: controllerFingerprint.uppercased(),
      controllerSignalName: "galaxyssi:phone"
    )
    let receipt = makeReceipt(for: baseRequest, pending: pending)
    let context = AgentDesktopControlReceiptVerificationContext(
      expectedSignerId: signerId,
      expectedSignatureKeyId: signatureKeyId,
      expectedControllerFingerprint: controllerFingerprint,
      pendingRequest: pending
    )
    let verifier: AgentDesktopControlReceiptSignatureVerifier = { _, _, payload, signature in
      signature == signedDigest(payload)
    }

    XCTAssertEqual(AgentDesktopControlReceiptProtocol.contractVersion, "galaxyssi.desktop-control/1.5")
    XCTAssertEqual(AgentDesktopControlReceiptProtocol.receiptVersion, 4)
    XCTAssertEqual(pending.toolId, AgentDesktopControlAction.screenshot)
    XCTAssertEqual(pending.requestSha256.count, 64)
    XCTAssertEqual(pending.inputSha256.count, 64)
    XCTAssertTrue(AgentDesktopControlReceiptProtocol.verify(payload: receipt, context: context, verifier: verifier))
    let parsed = try XCTUnwrap(AgentDesktopControlReceipt.parse(receipt))
    XCTAssertEqual(parsed.controllerAppInstanceId, "galaxyssi:phone")
    XCTAssertEqual(parsed.controllerName, "Test iPhone")
    XCTAssertEqual(parsed.controllerPlatform, "ios")
    XCTAssertEqual(parsed.controllerFingerprint, controllerFingerprint)
    XCTAssertEqual(parsed.startedAt, 1_800_000_000_500)
    XCTAssertEqual(parsed.durationMillis, 500)
    XCTAssertEqual(parsed.inputSha256, pending.inputSha256)

    var wrongController = context
    wrongController.expectedControllerFingerprint = AgentDesktopControlReceiptProtocol.digest(Data("other-phone".utf8))
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: receipt, context: wrongController, verifier: verifier))

    var tamperedSummary = receipt
    tamperedSummary["summary"] = .string("tampered")
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: tamperedSummary, context: context, verifier: verifier))

    var badTiming = receipt
    badTiming["started_at"] = .int(1_800_000_002_000)
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: badTiming, context: context, verifier: verifier))

    var badScreenshot = receipt
    if var output = badScreenshot["output"]?.objectValue,
       var screenshot = output["screenshot"]?.objectValue {
      screenshot["image_base64"] = .string(Data("tampered".utf8).base64EncodedString())
      output["screenshot"] = .object(screenshot)
      badScreenshot["output"] = .object(output)
    }
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(payload: badScreenshot, context: context, verifier: verifier))
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(
      payload: makeReceipt(
        for: baseRequest,
        pending: pending,
        screenshotBytes: Data(repeating: 0x5a, count: AgentDesktopScreenshotStreamPolicy.screenshotByteLimit + 1)
      ),
      context: context,
      verifier: verifier
    ))
    XCTAssertFalse(AgentDesktopControlReceiptProtocol.verify(
      payload: makeReceipt(for: baseRequest, pending: pending, screenshotBytes: Data([1, 2, 3, 4]), declaredBytes: 5),
      context: context,
      verifier: verifier
    ))
  }

  func testAgentDesktopControlPoliciesAndPerceptionSnapshotMirrorAndroid() throws {
    func frame(_ capturedAt: Int64) -> AgentDesktopControlScreenshot {
      AgentDesktopControlScreenshot(
        jpegBytes: Data([1]),
        width: 1,
        height: 1,
        originalWidth: 1,
        originalHeight: 1,
        capturedAt: capturedAt
      )
    }

    XCTAssertNil(AgentDesktopScreenshotStreamPolicy.normalizeFps(0))
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.normalizeFps(1), 1)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.normalizeFps(2), 2)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.normalizeFps(3), 3)
    XCTAssertNil(AgentDesktopScreenshotStreamPolicy.normalizeFps(4))
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.intervalMillis(1), 1_000)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.intervalMillis(2), 500)
    XCTAssertEqual(AgentDesktopScreenshotStreamPolicy.intervalMillis(3), 333)
    XCTAssertTrue(shouldApplyDesktopScreenshot(current: nil, candidate: frame(2_000)))
    XCTAssertTrue(shouldApplyDesktopScreenshot(current: frame(2_000), candidate: frame(2_000)))
    XCTAssertFalse(shouldApplyDesktopScreenshot(current: frame(2_000), candidate: frame(1_999)))

    let gate = AgentDesktopScreenshotRequestGate()
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-1", expiresAt: 2_000, now: 1_000))
    XCTAssertFalse(gate.claim(desktopId: "desktop-1", actionId: "action-2", expiresAt: 2_500, now: 1_500))
    gate.release(desktopId: "desktop-1", actionId: "wrong-action")
    XCTAssertFalse(gate.claim(desktopId: "desktop-1", actionId: "action-3", expiresAt: 2_500, now: 1_600))
    gate.release(desktopId: "desktop-1", actionId: "action-1")
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-4", expiresAt: 2_500, now: 1_700))
    XCTAssertTrue(gate.claim(desktopId: "desktop-2", actionId: "action-5", expiresAt: 2_500, now: 1_700))
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-6", expiresAt: 3_500, now: 2_501))
    gate.clear(desktopId: "desktop-1")
    XCTAssertTrue(gate.claim(desktopId: "desktop-1", actionId: "action-7", expiresAt: 4_000, now: 3_000))

    let snapshot = try XCTUnwrap(AgentDesktopPerceptionSnapshot.parse([
      "contract_version": .string(AgentDesktopPerceptionSnapshot.contractVersion),
      "capture_id": .string("capture-1"),
      "captured_at": .int(1_800_000_001_000),
      "duration_ms": .int(237),
      "untrusted_evidence": .bool(true),
      "preferred_grounding": .string("ui_tree"),
      "available_layers": .array([.string("ui_tree"), .string("ocr"), .string("screenshot")]),
      "active_window": .object([
        "title": .string("GalaxySSI"),
        "process_id": .int(42)
      ]),
      "screenshot_layer": .object(["status": .string("available")]),
      "ui_tree": .object([
        "status": .string("available"),
        "element_count": .int(1),
        "truncated": .bool(false),
        "elements": .array([
          .object([
            "id": .string("42.1"),
            "parent_id": .string(""),
            "depth": .int(99),
            "name": .string("Send"),
            "control_type": .string("Button"),
            "enabled": .bool(true),
            "focused": .bool(false),
            "offscreen": .bool(false),
            "password": .bool(false),
            "bounds": .object([
              "left": .int(10),
              "top": .int(20),
              "width": .int(80),
              "height": .int(40)
            ]),
            "actions": .array([.string("invoke"), .string("")])
          ])
        ])
      ]),
      "ocr": .object([
        "status": .string("available"),
        "text": .string("Send a message"),
        "character_count": .int(14),
        "line_count": .int(1),
        "truncated": .bool(false)
      ])
    ]))

    XCTAssertEqual(snapshot.captureId, "capture-1")
    XCTAssertEqual(snapshot.activeWindowTitle, "GalaxySSI")
    XCTAssertEqual(snapshot.availableLayers, ["ui_tree", "ocr", "screenshot"])
    XCTAssertEqual(snapshot.uiElementCount, 1)
    XCTAssertEqual(snapshot.uiElements.count, 1)
    XCTAssertEqual(snapshot.uiElements.first?.name, "Send")
    XCTAssertEqual(snapshot.uiElements.first?.depth, 12)
    XCTAssertEqual(snapshot.uiElements.first?.actions, ["invoke"])
    XCTAssertEqual(snapshot.ocrText, "Send a message")
    XCTAssertNil(AgentDesktopPerceptionSnapshot.parse([
      "contract_version": .string(AgentDesktopPerceptionSnapshot.contractVersion),
      "capture_id": .string("capture-1"),
      "captured_at": .int(1_800_000_001_000),
      "untrusted_evidence": .bool(false)
    ]))
  }

  func testAgentDesktopRunSummariesAndTaskControlDigestsMirrorAndroid() throws {
    let runs = AgentDesktopRunSummary.parseSummaries(.array([
      .object([
        "task_id": .string("task-running"),
        "conversation_id": .string("conversation-1"),
        "turn_id": .string("turn-1"),
        "agent_id": .string("codex"),
        "status": .string("running"),
        "prompt": .string("Build the project"),
        "current_step": .string("Running tests"),
        "updated_at": .int(1_800_000_000_000),
        "execution_view": .object([
          "pausable": .bool(true),
          "resumable": .bool(false),
          "takeover_available": .bool(false),
          "takeover_active": .bool(false)
        ])
      ]),
      .object([
        "task_id": .string("task-takeover"),
        "task_status": .string("takeover"),
        "execution_view": .object([
          "pausable": .bool(false),
          "resumable": .bool(true),
          "takeover_available": .bool(false),
          "takeover_active": .bool(true),
          "takeover": .object(["controller_name": .string("iPhone")])
        ])
      ]),
      .object(["status": .string("running")])
    ]))

    func request(toolId: String, targetTaskId: String) -> AgentMcpJSONObject {
      [
        "type": .string("desktop_executor_request"),
        "task_id": .string("desktop-control-action"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string("session-1"),
        "tool_id": .string(toolId),
        "input": .object(["task_id": .string(targetTaskId)]),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ]
    }

    let pause = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.taskPause, targetTaskId: "task-1"),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )
    let anotherTask = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.taskPause, targetTaskId: "task-2"),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )
    let continueRequest = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: request(toolId: AgentDesktopControlAction.taskContinue, targetTaskId: "task-1"),
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )
    let liveFrame = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: [
        "type": .string("desktop_executor_request"),
        "task_id": .string("desktop-control-action"),
        "action_id": .string("00000000-0000-4000-8000-000000000001"),
        "authorization_id": .string("00000000-0000-4000-8000-000000000002"),
        "desktop_session_id": .string("session-1"),
        "tool_id": .string(AgentDesktopControlAction.screenshot),
        "input": .object(["stream_frame": .bool(true), "stream_fps": .int(3)]),
        "sent_at": .int(1_800_000_000_000),
        "expires_at": .int(1_800_000_030_000)
      ],
      clientRouteId: "client-route-1",
      controllerFingerprint: "controller-fingerprint",
      controllerSignalName: "galaxyssi:phone"
    )

    XCTAssertEqual(runs.count, 2)
    XCTAssertEqual(runs[0].status, "running")
    XCTAssertEqual(runs[0].currentStep, "Running tests")
    XCTAssertTrue(runs[0].pausable)
    XCTAssertFalse(runs[0].resumable)
    XCTAssertEqual(runs[1].status, "takeover")
    XCTAssertTrue(runs[1].resumable)
    XCTAssertTrue(runs[1].takeoverActive)
    XCTAssertEqual(runs[1].takeoverController, "iPhone")
    XCTAssertEqual(AgentDesktopControlReceiptProtocol.contractVersion, "galaxyssi.desktop-control/1.5")
    XCTAssertTrue(AgentDesktopControlAction.toolIds.contains(AgentDesktopControlAction.taskTakeover))
    XCTAssertEqual(pause.toolId, AgentDesktopControlAction.taskPause)
    XCTAssertNotEqual(pause.inputSha256, anotherTask.inputSha256)
    XCTAssertNotEqual(pause.requestSha256, continueRequest.requestSha256)
    XCTAssertTrue(liveFrame.streamFrame)
    XCTAssertNotEqual(liveFrame.inputSha256, pause.inputSha256)
  }

}
