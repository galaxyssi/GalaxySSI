import CryptoKit
import Foundation

enum AgentDesktopControlAction {
  static let screenshot = "desktop.screenshot"
  static let perceive = "desktop.perceive"
  static let clickXY = "desktop.click_xy"
  static let typeText = "desktop.type_text"
  static let hotkey = "desktop.hotkey"
  static let scroll = "desktop.scroll"
  static let windowSwitch = "desktop.window_switch"
  static let fileSelect = "desktop.file_select"
  static let surfaceList = "desktop.surface.list"
  static let surfaceSelect = "desktop.surface.select"
  static let windowActivate = "desktop.window.activate"
  static let taskPause = "desktop.task_pause"
  static let taskTakeover = "desktop.task_takeover"
  static let taskContinue = "desktop.task_continue"
  static let taskRelease = "desktop.task_release"

  static let orderedToolIds = [
    screenshot,
    perceive,
    clickXY,
    typeText,
    hotkey,
    scroll,
    windowSwitch,
    fileSelect,
    surfaceList,
    surfaceSelect,
    windowActivate,
    taskPause,
    taskTakeover,
    taskContinue,
    taskRelease
  ]

  static let toolIds = Set(orderedToolIds)
}

enum AgentDesktopScreenshotStreamPolicy {
  static let screenshotByteLimit = 100_000
  static let minimumFPS = 1
  static let maximumFPS = 3

  static func normalizeFps(_ fps: Int) -> Int? {
    (minimumFPS...maximumFPS).contains(fps) ? fps : nil
  }

  static func intervalMillis(_ fps: Int) -> Int64? {
    guard let normalized = normalizeFps(fps) else { return nil }
    return 1_000 / Int64(normalized)
  }
}

struct AgentDesktopControlAuthorization: Codable, Equatable, Identifiable {
  var authorizationId: String
  var appInstanceId: String
  var appName: String
  var appPlatform: String
  var phoneName: String
  var phoneFingerprint: String
  var grantSource: String
  var accessProfile: String
  var accessScopes: [String]
  var grantedAt: Int64
  var lastUsedAt: Int64
  var revokedAt: Int64
  var revokeReason: String
  var status: String
  var allowedTools: [String]
  var desktopSessionId: String
  var desktopSessionExpiresAt: Int64

  var id: String { authorizationId }

  enum CodingKeys: String, CodingKey {
    case authorizationId = "authorization_id"
    case appInstanceId = "app_instance_id"
    case appName = "app_name"
    case appPlatform = "app_platform"
    case phoneName = "phone_name"
    case phoneFingerprint = "phone_fingerprint"
    case grantSource = "grant_source"
    case accessProfile = "access_profile"
    case accessScopes = "access_scopes"
    case grantedAt = "granted_at"
    case lastUsedAt = "last_used_at"
    case revokedAt = "revoked_at"
    case revokeReason = "revoke_reason"
    case status
    case allowedTools = "allowed_tools"
    case desktopSessionId = "desktop_session_id"
    case desktopSessionExpiresAt = "desktop_session_expires_at"
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopControlAuthorization? {
    guard let source else { return nil }
    let status = source.string("status")
    let authorizationId = source.string("authorization_id")
    if authorizationId.isBlank && status != "pending" {
      return nil
    }
    return AgentDesktopControlAuthorization(
      authorizationId: authorizationId,
      appInstanceId: source.string("app_instance_id"),
      appName: source.string("app_name").nonEmpty ?? source.string("phone_name"),
      appPlatform: source.string("app_platform").nonEmpty ?? source.string("platform"),
      phoneName: source.string("phone_name"),
      phoneFingerprint: source.string("app_identity_fingerprint").nonEmpty ?? source.string("phone_fingerprint"),
      grantSource: source.string("grant_source"),
      accessProfile: source.string("access_profile"),
      accessScopes: AgentDesktopControlJSON.stringArray(source["access_scopes"]),
      grantedAt: source.int64("granted_at"),
      lastUsedAt: source.int64("last_used_at"),
      revokedAt: source.int64("revoked_at"),
      revokeReason: source.string("revoke_reason"),
      status: status,
      allowedTools: AgentDesktopControlJSON.stringArray(source["allowed_tools"]),
      desktopSessionId: source.string("desktop_session_id"),
      desktopSessionExpiresAt: source.int64("desktop_session_expires_at")
    )
  }
}

struct AgentDesktopControlScreenshot: Equatable {
  var jpegBytes: Data
  var width: Int
  var height: Int
  var originalWidth: Int
  var originalHeight: Int
  var capturedAt: Int64

  static func parse(
    _ source: AgentMcpJSONObject?,
    defaultCapturedAt: Int64 = 0
  ) -> AgentDesktopControlScreenshot? {
    guard let source,
          source.string("image_mime") == "image/jpeg",
          let encoded = source.string("image_base64").nonEmpty,
          let bytes = Data(base64Encoded: encoded),
          !bytes.isEmpty,
          bytes.count <= AgentDesktopScreenshotStreamPolicy.screenshotByteLimit else {
      return nil
    }
    let declaredBytes = source["bytes"]?.intValue ?? Int64(bytes.count)
    guard declaredBytes == Int64(bytes.count) else {
      return nil
    }
    let screenshot = AgentDesktopControlScreenshot(
      jpegBytes: bytes,
      width: max(0, Int(source.int64("width"))),
      height: max(0, Int(source.int64("height"))),
      originalWidth: max(0, Int(source.int64("original_width"))),
      originalHeight: max(0, Int(source.int64("original_height"))),
      capturedAt: source["captured_at"]?.intValue ?? defaultCapturedAt
    )
    guard screenshot.width > 0,
          screenshot.height > 0,
          screenshot.originalWidth > 0,
          screenshot.originalHeight > 0 else {
      return nil
    }
    return screenshot
  }
}

struct AgentDesktopSurfaceBounds: Codable, Equatable {
  var left: Int
  var top: Int
  var width: Int
  var height: Int

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopSurfaceBounds {
    let source = source ?? [:]
    return AgentDesktopSurfaceBounds(
      left: Int(source.int64("left")),
      top: Int(source.int64("top")),
      width: max(0, Int(source.int64("width"))),
      height: max(0, Int(source.int64("height")))
    )
  }
}

struct AgentDesktopDisplaySurface: Codable, Equatable, Identifiable {
  var displayId: String
  var name: String
  var bounds: AgentDesktopSurfaceBounds
  var primary: Bool

  var id: String { displayId }

  enum CodingKeys: String, CodingKey {
    case displayId = "display_id"
    case name
    case bounds
    case primary
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopDisplaySurface? {
    guard let source else { return nil }
    let displayId = source.clippedString("display_id", limit: 120)
    guard !displayId.isBlank else { return nil }
    return AgentDesktopDisplaySurface(
      displayId: displayId,
      name: source.clippedString("name", limit: 120),
      bounds: AgentDesktopSurfaceBounds.parse(source.object("bounds")),
      primary: source.bool("primary")
    )
  }
}

struct AgentDesktopWindowSurface: Codable, Equatable, Identifiable {
  var windowId: String
  var title: String
  var displayId: String
  var bounds: AgentDesktopSurfaceBounds
  var foreground: Bool
  var minimized: Bool

  var id: String { windowId }

  enum CodingKeys: String, CodingKey {
    case windowId = "window_id"
    case title
    case displayId = "display_id"
    case bounds
    case foreground
    case minimized
  }

  static func parse(
    _ source: AgentMcpJSONObject?,
    allowedDisplayIds: Set<String>
  ) -> AgentDesktopWindowSurface? {
    guard let source else { return nil }
    let windowId = source.clippedString("window_id", limit: 120)
    let displayId = source.clippedString("display_id", limit: 120)
    guard !windowId.isBlank,
          allowedDisplayIds.contains(displayId) else {
      return nil
    }
    return AgentDesktopWindowSurface(
      windowId: windowId,
      title: source.clippedString("title", limit: 500),
      displayId: displayId,
      bounds: AgentDesktopSurfaceBounds.parse(source.object("bounds")),
      foreground: source.bool("foreground"),
      minimized: source.bool("minimized")
    )
  }
}

struct AgentDesktopSurfaceSelection: Codable, Equatable {
  var displayId: String
  var windowId: String
  var targetKind: String

  enum CodingKeys: String, CodingKey {
    case displayId = "selected_display_id"
    case windowId = "selected_window_id"
    case targetKind = "target_kind"
  }
}

struct AgentDesktopSurfaceCatalog: Codable, Equatable {
  static let contractVersion = "galaxyssi.desktop-surfaces/1.0"

  var displays: [AgentDesktopDisplaySurface]
  var windows: [AgentDesktopWindowSurface]
  var selection: AgentDesktopSurfaceSelection
  var targetTitle: String
  var targetBounds: AgentDesktopSurfaceBounds

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopSurfaceCatalog? {
    guard let source,
          source.string("surface_contract") == contractVersion else {
      return nil
    }
    let displays = (source["displays"]?.arrayValue ?? [])
      .prefix(16)
      .compactMap { AgentDesktopDisplaySurface.parse($0.objectValue) }
    guard !displays.isEmpty else { return nil }
    let displayIds = Set(displays.map(\.displayId))
    let windows = (source["windows"]?.arrayValue ?? [])
      .prefix(100)
      .compactMap { AgentDesktopWindowSurface.parse($0.objectValue, allowedDisplayIds: displayIds) }
    let selection = source.object("selection") ?? [:]
    let target = source.object("target") ?? [:]
    return AgentDesktopSurfaceCatalog(
      displays: displays,
      windows: windows,
      selection: AgentDesktopSurfaceSelection(
        displayId: selection.clippedString("selected_display_id", limit: 120),
        windowId: selection.clippedString("selected_window_id", limit: 120),
        targetKind: selection.clippedString("target_kind", limit: 20)
      ),
      targetTitle: target.clippedString("title", limit: 500),
      targetBounds: AgentDesktopSurfaceBounds.parse(target.object("bounds"))
    )
  }

  static func parseOutput(_ source: AgentMcpJSONObject?) -> AgentDesktopSurfaceCatalog? {
    parse(source?.object("surface_catalog"))
  }
}

func shouldApplyDesktopScreenshot(
  current: AgentDesktopControlScreenshot?,
  candidate: AgentDesktopControlScreenshot
) -> Bool {
  current == nil || candidate.capturedAt >= (current?.capturedAt ?? 0)
}

struct AgentDesktopPerceptionElement: Codable, Equatable, Identifiable {
  var id: String
  var parentId: String
  var depth: Int
  var name: String
  var controlType: String
  var automationId: String
  var className: String
  var left: Int
  var top: Int
  var width: Int
  var height: Int
  var enabled: Bool
  var focused: Bool
  var offscreen: Bool
  var password: Bool
  var actions: [String]

  enum CodingKeys: String, CodingKey {
    case id
    case parentId = "parent_id"
    case depth
    case name
    case controlType = "control_type"
    case automationId = "automation_id"
    case className = "class_name"
    case left
    case top
    case width
    case height
    case enabled
    case focused
    case offscreen
    case password
    case actions
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopPerceptionElement? {
    guard let source else { return nil }
    let bounds = source.object("bounds") ?? [:]
    return AgentDesktopPerceptionElement(
      id: source.clippedString("id", limit: 160),
      parentId: source.clippedString("parent_id", limit: 160),
      depth: Int(source.int64("depth")).clamped(to: 0...12),
      name: source.clippedString("name", limit: 500),
      controlType: source.clippedString("control_type", limit: 120),
      automationId: source.clippedString("automation_id", limit: 240),
      className: source.clippedString("class_name", limit: 240),
      left: Int(bounds.int64("left")),
      top: Int(bounds.int64("top")),
      width: max(0, Int(bounds.int64("width"))),
      height: max(0, Int(bounds.int64("height"))),
      enabled: source.bool("enabled"),
      focused: source.bool("focused"),
      offscreen: source.bool("offscreen"),
      password: source.bool("password"),
      actions: AgentDesktopControlJSON.stringArray(source["actions"], maxItems: 12, maxCharacters: 64, dropBlank: true)
    )
  }
}

struct AgentDesktopPerceptionSnapshot: Codable, Equatable, Identifiable {
  static let contractVersion = "galaxyssi.desktop-perception/1.0"

  var captureId: String
  var capturedAt: Int64
  var durationMillis: Int64
  var activeWindowTitle: String
  var activeWindowProcessId: Int
  var availableLayers: [String]
  var preferredGrounding: String
  var screenshotStatus: String
  var uiTreeStatus: String
  var uiTreeError: String
  var uiElements: [AgentDesktopPerceptionElement]
  var uiElementCount: Int
  var uiTreeTruncated: Bool
  var ocrStatus: String
  var ocrError: String
  var ocrText: String
  var ocrCharacterCount: Int
  var ocrLineCount: Int
  var ocrTruncated: Bool

  var id: String { captureId }

  enum CodingKeys: String, CodingKey {
    case captureId = "capture_id"
    case capturedAt = "captured_at"
    case durationMillis = "duration_ms"
    case activeWindowTitle = "active_window_title"
    case activeWindowProcessId = "active_window_process_id"
    case availableLayers = "available_layers"
    case preferredGrounding = "preferred_grounding"
    case screenshotStatus = "screenshot_status"
    case uiTreeStatus = "ui_tree_status"
    case uiTreeError = "ui_tree_error"
    case uiElements = "ui_elements"
    case uiElementCount = "ui_element_count"
    case uiTreeTruncated = "ui_tree_truncated"
    case ocrStatus = "ocr_status"
    case ocrError = "ocr_error"
    case ocrText = "ocr_text"
    case ocrCharacterCount = "ocr_character_count"
    case ocrLineCount = "ocr_line_count"
    case ocrTruncated = "ocr_truncated"
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopPerceptionSnapshot? {
    guard let source,
          source.string("contract_version") == contractVersion else {
      return nil
    }
    let captureId = source.string("capture_id")
    let capturedAt = source.int64("captured_at")
    guard !captureId.isBlank,
          capturedAt > 0,
          source.bool("untrusted_evidence") else {
      return nil
    }
    let activeWindow = source.object("active_window") ?? [:]
    let uiTree = source.object("ui_tree") ?? [:]
    let ocr = source.object("ocr") ?? [:]
    let screenshotLayer = source.object("screenshot_layer") ?? [:]
    let elements = (uiTree["elements"]?.arrayValue ?? [])
      .prefix(120)
      .compactMap { AgentDesktopPerceptionElement.parse($0.objectValue) }
    let declaredElementCount = Int(uiTree["element_count"]?.intValue ?? Int64(elements.count))
    return AgentDesktopPerceptionSnapshot(
      captureId: captureId,
      capturedAt: capturedAt,
      durationMillis: max(0, source.int64("duration_ms")),
      activeWindowTitle: activeWindow.clippedString("title", limit: 500),
      activeWindowProcessId: max(0, Int(activeWindow.int64("process_id"))),
      availableLayers: AgentDesktopControlJSON.stringArray(
        source["available_layers"],
        maxCharacters: 40,
        dropBlank: true
      ),
      preferredGrounding: source.clippedString("preferred_grounding", limit: 40),
      screenshotStatus: screenshotLayer.clippedString("status", limit: 40),
      uiTreeStatus: uiTree.clippedString("status", limit: 40),
      uiTreeError: (uiTree.object("error") ?? [:]).clippedString("message", limit: 500),
      uiElements: Array(elements),
      uiElementCount: max(declaredElementCount, elements.count),
      uiTreeTruncated: uiTree.bool("truncated"),
      ocrStatus: ocr.clippedString("status", limit: 40),
      ocrError: (ocr.object("error") ?? [:]).clippedString("message", limit: 500),
      ocrText: ocr.clippedString("text", limit: 24_000),
      ocrCharacterCount: max(0, Int(ocr.int64("character_count"))),
      ocrLineCount: max(0, Int(ocr.int64("line_count"))),
      ocrTruncated: ocr.bool("truncated")
    )
  }
}

struct AgentDesktopControlAudit: Codable, Equatable {
  var eventType: String
  var toolId: String
  var status: String
  var summary: String
  var createdAt: Int64

  enum CodingKeys: String, CodingKey {
    case eventType = "event_type"
    case toolId = "tool_id"
    case status
    case summary
    case createdAt = "created_at"
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopControlAudit? {
    guard let source else { return nil }
    return AgentDesktopControlAudit(
      eventType: source.string("event_type"),
      toolId: source.string("tool_id"),
      status: source.string("status"),
      summary: source.string("summary"),
      createdAt: source.int64("created_at")
    )
  }
}

struct AgentDesktopControlReceipt: Codable, Equatable, Identifiable {
  var receiptId: String
  var taskId: String
  var actionId: String
  var authorizationId: String
  var desktopSessionId: String
  var toolId: String
  var status: String
  var summary: String
  var errorCode: String
  var errorRetryable: Bool
  var requestSha256: String
  var inputSha256: String
  var outputSha256: String
  var evidenceSha256: String
  var controllerAppInstanceId: String
  var controllerName: String
  var controllerPlatform: String
  var controllerFingerprint: String
  var signerId: String
  var signatureKeyId: String
  var startedAt: Int64
  var completedAt: Int64
  var durationMillis: Int64

  var id: String { receiptId }

  enum CodingKeys: String, CodingKey {
    case receiptId = "receipt_id"
    case taskId = "task_id"
    case actionId = "action_id"
    case authorizationId = "authorization_id"
    case desktopSessionId = "desktop_session_id"
    case toolId = "tool_id"
    case status
    case summary
    case errorCode = "error_code"
    case errorRetryable = "error_retryable"
    case requestSha256 = "request_sha256"
    case inputSha256 = "input_sha256"
    case outputSha256 = "output_sha256"
    case evidenceSha256 = "evidence_sha256"
    case controllerAppInstanceId = "controller_app_instance_id"
    case controllerName = "controller_name"
    case controllerPlatform = "controller_platform"
    case controllerFingerprint = "controller_fingerprint"
    case signerId = "signer_id"
    case signatureKeyId = "signature_key_id"
    case startedAt = "started_at"
    case completedAt = "completed_at"
    case durationMillis = "duration_ms"
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopControlReceipt? {
    guard let source else { return nil }
    let receiptId = source.string("receipt_id")
    guard !receiptId.isBlank else { return nil }
    return AgentDesktopControlReceipt(
      receiptId: receiptId,
      taskId: source.string("task_id"),
      actionId: source.string("action_id"),
      authorizationId: source.string("authorization_id"),
      desktopSessionId: source.string("desktop_session_id"),
      toolId: source.string("tool_id"),
      status: source.string("status"),
      summary: source.string("summary"),
      errorCode: source.string("error_code"),
      errorRetryable: source.bool("error_retryable"),
      requestSha256: source.string("request_sha256"),
      inputSha256: source.string("input_sha256"),
      outputSha256: source.string("output_sha256"),
      evidenceSha256: source.string("evidence_sha256"),
      controllerAppInstanceId: source.string("controller_app_instance_id"),
      controllerName: source.string("controller_name"),
      controllerPlatform: source.string("controller_platform"),
      controllerFingerprint: source.string("controller_fingerprint"),
      signerId: source.string("signer_id"),
      signatureKeyId: source.string("signature_key_id"),
      startedAt: source.int64("started_at"),
      completedAt: source.int64("completed_at"),
      durationMillis: source.int64("duration_ms")
    )
  }
}

struct AgentDesktopRunSummary: Codable, Equatable, Identifiable {
  var taskId: String
  var conversationId: String
  var turnId: String
  var agentId: String
  var status: String
  var prompt: String
  var currentStep: String
  var updatedAt: Int64
  var pausable: Bool
  var resumable: Bool
  var takeoverAvailable: Bool
  var takeoverActive: Bool
  var takeoverController: String

  var id: String { taskId }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case agentId = "agent_id"
    case status
    case prompt
    case currentStep = "current_step"
    case updatedAt = "updated_at"
    case pausable
    case resumable
    case takeoverAvailable = "takeover_available"
    case takeoverActive = "takeover_active"
    case takeoverController = "takeover_controller"
  }

  static func parseSummaries(_ value: AgentMcpJSONValue?) -> [AgentDesktopRunSummary] {
    switch value {
    case .some(.array(let values)):
      return values.compactMap { parse($0.objectValue) }
    case .some(.object(let object)):
      return parse(object).map { [$0] } ?? []
    case .some(.string), .some(.int), .some(.double), .some(.bool), .some(.null), .none:
      return []
    }
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopRunSummary? {
    guard let source else { return nil }
    let taskId = source.string("task_id")
    guard !taskId.isBlank else { return nil }
    let view = source.object("execution_view") ?? [:]
    let takeover = source.object("takeover") ?? view.object("takeover") ?? [:]
    return AgentDesktopRunSummary(
      taskId: taskId,
      conversationId: source.string("conversation_id"),
      turnId: source.string("turn_id"),
      agentId: source.string("agent_id"),
      status: source.string("status").nonEmpty ?? source.string("task_status"),
      prompt: source.string("prompt"),
      currentStep: source.string("current_step"),
      updatedAt: source.int64("updated_at"),
      pausable: view.bool("pausable"),
      resumable: view.bool("resumable"),
      takeoverAvailable: view.bool("takeover_available"),
      takeoverActive: view.bool("takeover_active"),
      takeoverController: takeover.string("controller_name")
    )
  }
}

struct AgentDesktopRemoteControlSnapshot: Equatable {
  var desktopId: String
  var desktopName: String
  var desktopFingerprint: String
  var serverRouteId: String
  var fullDesktopExecutor: Bool
  var enabled: Bool
  var requireUnlocked: Bool
  var currentAuthorization: AgentDesktopControlAuthorization?
  var authorizations: [AgentDesktopControlAuthorization]
  var recentAudit: [AgentDesktopControlAudit]
  var recentReceipts: [AgentDesktopControlReceipt]
  var activeRuns: [AgentDesktopRunSummary]
  var lastActionStatus: String
  var lastActionSummary: String
  var lastActionAt: Int64
  var screenshot: AgentDesktopControlScreenshot?
  var perception: AgentDesktopPerceptionSnapshot?
  var surfaceCatalog: AgentDesktopSurfaceCatalog?
  var streamFps: Int
  var streamActive: Bool

  var authorized: Bool {
    fullDesktopExecutor && enabled && currentAuthorization?.status == "active"
  }

  var pending: Bool {
    fullDesktopExecutor && currentAuthorization?.status == "pending"
  }

  static func initial(for link: ServerLink) -> AgentDesktopRemoteControlSnapshot {
    AgentDesktopRemoteControlSnapshot(
      desktopId: link.desktopId,
      desktopName: link.desktopName.ifBlank("GalaxySSI Desktop"),
      desktopFingerprint: link.desktopFingerprint,
      serverRouteId: link.routes.clientRouteId,
      fullDesktopExecutor: link.fullDesktopExecutor,
      enabled: link.fullDesktopExecutor,
      requireUnlocked: false,
      currentAuthorization: nil,
      authorizations: [],
      recentAudit: [],
      recentReceipts: [],
      activeRuns: [],
      lastActionStatus: "",
      lastActionSummary: "",
      lastActionAt: 0,
      screenshot: nil,
      perception: nil,
      surfaceCatalog: nil,
      streamFps: 0,
      streamActive: false
    )
  }

  static func parse(_ source: AgentMcpJSONObject?) -> AgentDesktopRemoteControlSnapshot? {
    guard let source else { return nil }
    let authorizations = parseAuthorizations(source["authorizations"])
    let currentAuthorization = AgentDesktopControlAuthorization.parse(source.object("current_authorization"))
      ?? authorizations.first { $0.status == "active" }
      ?? authorizations.first { $0.status == "pending" }
    let fps = Int(source.int64("stream_fps"))
    return AgentDesktopRemoteControlSnapshot(
      desktopId: source.string("desktop_id"),
      desktopName: source.string("desktop_name").nonEmpty ?? "GalaxySSI Desktop",
      desktopFingerprint: source.string("desktop_fingerprint"),
      serverRouteId: source.string("server_route_id"),
      fullDesktopExecutor: source.bool("full_desktop_executor"),
      enabled: source.bool("enabled"),
      requireUnlocked: source.bool("require_unlocked"),
      currentAuthorization: currentAuthorization,
      authorizations: authorizations,
      recentAudit: parseAudit(source["recent_audit"]),
      recentReceipts: parseReceipts(source["recent_receipts"]),
      activeRuns: AgentDesktopRunSummary.parseSummaries(source["active_runs"]),
      lastActionStatus: source.string("last_action_status"),
      lastActionSummary: source.string("last_action_summary"),
      lastActionAt: source.int64("last_action_at"),
      screenshot: AgentDesktopControlScreenshot.parse(
        source.object("screenshot"),
        defaultCapturedAt: source.int64("last_action_at")
      ),
      perception: AgentDesktopPerceptionSnapshot.parse(source.object("perception")),
      surfaceCatalog: AgentDesktopSurfaceCatalog.parse(source.object("surface_catalog")),
      streamFps: AgentDesktopScreenshotStreamPolicy.normalizeFps(fps) ?? 0,
      streamActive: source.bool("stream_active")
    )
  }

  static func parseAuthorizations(_ value: AgentMcpJSONValue?) -> [AgentDesktopControlAuthorization] {
    switch value {
    case .some(.array(let values)):
      return values.compactMap { AgentDesktopControlAuthorization.parse($0.objectValue) }
    case .some(.object(let object)):
      return AgentDesktopControlAuthorization.parse(object).map { [$0] } ?? []
    case .some(.string), .some(.int), .some(.double), .some(.bool), .some(.null), .none:
      return []
    }
  }

  static func parseAudit(_ value: AgentMcpJSONValue?) -> [AgentDesktopControlAudit] {
    switch value {
    case .some(.array(let values)):
      return values.compactMap { AgentDesktopControlAudit.parse($0.objectValue) }
    case .some(.object(let object)):
      return AgentDesktopControlAudit.parse(object).map { [$0] } ?? []
    case .some(.string), .some(.int), .some(.double), .some(.bool), .some(.null), .none:
      return []
    }
  }

  static func parseReceipts(_ value: AgentMcpJSONValue?) -> [AgentDesktopControlReceipt] {
    switch value {
    case .some(.array(let values)):
      return values.compactMap { AgentDesktopControlReceipt.parse($0.objectValue) }
    case .some(.object(let object)):
      return AgentDesktopControlReceipt.parse(object).map { [$0] } ?? []
    case .some(.string), .some(.int), .some(.double), .some(.bool), .some(.null), .none:
      return []
    }
  }
}

struct AgentDesktopControlPendingRequest: Equatable {
  var actionId: String
  var desktopId: String
  var toolId: String
  var desktopSessionId: String
  var requestSha256: String
  var inputSha256: String
  var expiresAt: Int64
  var streamFrame: Bool
}

struct AgentDesktopControlRequestRoutingContext: Equatable {
  var clientRouteId: String
  var controllerFingerprint: String
  var controllerSignalName: String
}

struct AgentDesktopControlActionRequest: Equatable {
  var desktopId: String
  var toolId: String
  var input: AgentMcpJSONObject
  var payload: AgentMcpJSONObject
  var pendingRequest: AgentDesktopControlPendingRequest
  var durable: Bool
  var resetsSurfaceState: Bool

  var actionId: String { pendingRequest.actionId }
  var expiresAt: Int64 { pendingRequest.expiresAt }
  var updatesRuntimeStatus: Bool { !pendingRequest.streamFrame }
}

enum AgentDesktopControlRequestFactory {
  static let actionTTLMillis: Int64 = 30_000

  static func screenshot(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.screenshot,
      input: [:],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func screenshotStreamFrame(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    fps: Int,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard let normalized = AgentDesktopScreenshotStreamPolicy.normalizeFps(fps) else {
      return nil
    }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.screenshot,
      input: [
        "stream_frame": .bool(true),
        "stream_fps": .int(Int64(normalized))
      ],
      actionId: actionId,
      nowMillis: nowMillis,
      durable: false
    )
  }

  static func perception(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.perceive,
      input: [
        "include_screenshot": .bool(true),
        "include_ocr": .bool(true),
        "include_ui_tree": .bool(true),
        "max_elements": .int(80),
        "max_depth": .int(8),
        "max_ocr_chars": .int(12_000)
      ],
      actionId: actionId,
      nowMillis: nowMillis,
      durable: false
    )
  }

  static func surfaces(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.surfaceList,
      input: [:],
      actionId: actionId,
      nowMillis: nowMillis,
      durable: false
    )
  }

  static func selectDisplay(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    displayId: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !displayId.isBlank else { return nil }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.surfaceSelect,
      input: ["display_id": .string(displayId)],
      actionId: actionId,
      nowMillis: nowMillis,
      durable: false,
      resetsSurfaceState: true
    )
  }

  static func selectWindow(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    windowId: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !windowId.isBlank else { return nil }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.surfaceSelect,
      input: ["window_id": .string(windowId)],
      actionId: actionId,
      nowMillis: nowMillis,
      durable: false,
      resetsSurfaceState: true
    )
  }

  static func activateWindow(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    windowId: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !windowId.isBlank else { return nil }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.windowActivate,
      input: ["window_id": .string(windowId)],
      actionId: actionId,
      nowMillis: nowMillis,
      resetsSurfaceState: true
    )
  }

  static func click(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    x: Int,
    y: Int,
    coordinateWidth: Int = 0,
    coordinateHeight: Int = 0,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    var input: AgentMcpJSONObject = [
      "x": .int(Int64(x)),
      "y": .int(Int64(y)),
      "button": .string("left")
    ]
    if coordinateWidth > 0 && coordinateHeight > 0 {
      input["coordinate_width"] = .int(Int64(coordinateWidth))
      input["coordinate_height"] = .int(Int64(coordinateHeight))
    }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.clickXY,
      input: input,
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func typeText(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    text: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !text.isBlank,
          text.count <= 4_096 else {
      return nil
    }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.typeText,
      input: ["text": .string(text)],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func hotkey(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    keys: [String],
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !keys.isEmpty,
          keys.count <= 4 else {
      return nil
    }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.hotkey,
      input: ["keys": .array(keys.map { .string($0) })],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func scroll(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    delta: Int,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard delta != 0,
          (-2_400...2_400).contains(delta) else {
      return nil
    }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.scroll,
      input: ["delta": .int(Int64(delta))],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func windowSwitch(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    previous: Bool = false,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.windowSwitch,
      input: ["direction": .string(previous ? "previous" : "next")],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func selectFile(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    path: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !path.isBlank,
          path.count <= 32_767 else {
      return nil
    }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.fileSelect,
      input: ["path": .string(path)],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func pauseTask(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    taskId: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !taskId.isBlank else { return nil }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.taskPause,
      input: ["task_id": .string(taskId)],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func takeOverTask(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    taskId: String,
    leaseSeconds: Int = 900,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !taskId.isBlank else { return nil }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.taskTakeover,
      input: [
        "task_id": .string(taskId),
        "lease_seconds": .int(Int64(leaseSeconds.clamped(to: 30...3_600)))
      ],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func continueTask(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    taskId: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !taskId.isBlank else { return nil }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.taskContinue,
      input: ["task_id": .string(taskId)],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  static func releaseTask(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    taskId: String,
    actionId: String = UUID().uuidString,
    nowMillis: Int64
  ) -> AgentDesktopControlActionRequest? {
    guard !taskId.isBlank else { return nil }
    return requestAction(
      snapshot: snapshot,
      routing: routing,
      toolId: AgentDesktopControlAction.taskRelease,
      input: ["task_id": .string(taskId)],
      actionId: actionId,
      nowMillis: nowMillis
    )
  }

  private static func requestAction(
    snapshot: AgentDesktopRemoteControlSnapshot,
    routing: AgentDesktopControlRequestRoutingContext,
    toolId: String,
    input: AgentMcpJSONObject,
    actionId: String,
    nowMillis: Int64,
    durable: Bool = true,
    resetsSurfaceState: Bool = false
  ) -> AgentDesktopControlActionRequest? {
    guard !snapshot.desktopId.isBlank,
          let authorization = snapshot.currentAuthorization,
          authorization.status == "active",
          !authorization.desktopSessionId.isBlank,
          authorization.desktopSessionExpiresAt > nowMillis else {
      return nil
    }
    let expiresAt = nowMillis + actionTTLMillis
    let payload: AgentMcpJSONObject = [
      "type": .string("desktop_executor_request"),
      "task_id": .string("desktop-control-\(actionId)"),
      "action_id": .string(actionId),
      "authorization_id": .string(authorization.authorizationId),
      "desktop_session_id": .string(authorization.desktopSessionId),
      "tool_id": .string(toolId),
      "input": .object(input),
      "sent_at": .int(nowMillis),
      "expires_at": .int(expiresAt)
    ]
    let pending = AgentDesktopControlReceiptProtocol.pendingRequest(
      payload: payload,
      clientRouteId: routing.clientRouteId,
      controllerFingerprint: routing.controllerFingerprint,
      controllerSignalName: routing.controllerSignalName,
      desktopId: snapshot.desktopId
    )
    return AgentDesktopControlActionRequest(
      desktopId: snapshot.desktopId,
      toolId: toolId,
      input: input,
      payload: payload,
      pendingRequest: pending,
      durable: durable,
      resetsSurfaceState: resetsSurfaceState
    )
  }
}

final class AgentDesktopScreenshotRequestGate {
  private struct Pending {
    var actionId: String
    var expiresAt: Int64
  }

  private var pending: [String: Pending] = [:]
  private let lock = NSLock()

  @discardableResult
  func claim(desktopId: String, actionId: String, expiresAt: Int64, now: Int64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let current = pending[desktopId], current.expiresAt >= now {
      return false
    }
    pending[desktopId] = Pending(actionId: actionId, expiresAt: expiresAt)
    return true
  }

  func release(desktopId: String, actionId: String) {
    lock.lock()
    defer { lock.unlock() }
    if pending[desktopId]?.actionId == actionId {
      pending.removeValue(forKey: desktopId)
    }
  }

  func clear(desktopId: String) {
    lock.lock()
    defer { lock.unlock() }
    pending.removeValue(forKey: desktopId)
  }
}

struct AgentDesktopControlReceiptVerificationContext {
  var expectedSignerId: String
  var expectedSignatureKeyId: String
  var expectedControllerFingerprint: String
  var pendingRequest: AgentDesktopControlPendingRequest?
}

typealias AgentDesktopControlReceiptSignatureVerifier = (
  _ signerId: String,
  _ signatureKeyId: String,
  _ payload: Data,
  _ signature: String
) -> Bool

enum AgentDesktopControlReceiptProtocol {
  static let contractVersion = "galaxyssi.desktop-control/1.5"
  static let receiptVersion = 4

  static func pendingRequest(
    payload: AgentMcpJSONObject,
    clientRouteId: String,
    controllerFingerprint: String,
    controllerSignalName: String,
    desktopId: String = ""
  ) -> AgentDesktopControlPendingRequest {
    let input = payload.object("input") ?? [:]
    let actionId = payload.string("action_id")
    return AgentDesktopControlPendingRequest(
      actionId: actionId,
      desktopId: desktopId,
      toolId: payload.string("tool_id"),
      desktopSessionId: payload.string("desktop_session_id"),
      requestSha256: digest([
        "contract_version": .string(contractVersion),
        "type": .string("desktop_executor_request"),
        "task_id": .string(payload.string("task_id")),
        "action_id": .string(actionId),
        "authorization_id": .string(payload.string("authorization_id")),
        "desktop_session_id": .string(payload.string("desktop_session_id")),
        "tool_id": .string(payload.string("tool_id")),
        "input": .object(input),
        "sent_at": .int(payload.int64("sent_at")),
        "expires_at": .int(payload.int64("expires_at")),
        "client_route_id": .string(clientRouteId),
        "controller_fingerprint": .string(controllerFingerprint.lowercased()),
        "controller_signal_name": .string(controllerSignalName)
      ]),
      inputSha256: digest(input),
      expiresAt: payload.int64("expires_at"),
      streamFrame: input.bool("stream_frame")
    )
  }

  static func verify(
    payload: AgentMcpJSONObject,
    context: AgentDesktopControlReceiptVerificationContext,
    verifier: AgentDesktopControlReceiptSignatureVerifier
  ) -> Bool {
    guard payload.int64("receipt_version") == Int64(receiptVersion) else {
      return false
    }
    let signerId = payload.string("signer_id")
    let signatureKeyId = payload.string("signature_key_id").lowercased()
    let controllerFingerprint = payload.string("controller_fingerprint").lowercased()
    let status = payload.string("status")
    let startedAt = payload.int64("started_at")
    let completedAt = payload.int64("completed_at")
    let durationMillis = payload.int64("duration_ms")

    guard signerId == context.expectedSignerId,
          signatureKeyId == context.expectedSignatureKeyId.lowercased(),
          controllerFingerprint == context.expectedControllerFingerprint.lowercased(),
          !payload.string("controller_app_instance_id").isBlank,
          !payload.string("controller_name").isBlank,
          !payload.string("controller_platform").isBlank,
          ["succeeded", "failed"].contains(status),
          startedAt > 0,
          completedAt >= startedAt,
          durationMillis == completedAt - startedAt else {
      return false
    }

    let requestSha256 = payload.string("request_sha256")
    let inputSha256 = payload.string("input_sha256")
    guard validDigest(requestSha256),
          validDigest(inputSha256) else {
      return false
    }

    if let pending = context.pendingRequest {
      guard pending.actionId == payload.string("action_id"),
            pending.desktopSessionId == payload.string("desktop_session_id"),
            pending.requestSha256 == requestSha256,
            pending.inputSha256 == inputSha256 else {
        return false
      }
    }

    let evidence = payload.object("post_screenshot") ?? payload.object("output")?.object("screenshot")
    let evidenceSha256 = payload.string("evidence_sha256")
    if !evidenceSha256.isBlank && !validDigest(evidenceSha256) {
      return false
    }
    if let evidence {
      guard evidence.string("image_mime") == "image/jpeg" else {
        return false
      }
      if let encoded = evidence.string("image_base64").nonEmpty {
        guard let bytes = Data(base64Encoded: encoded),
              !bytes.isEmpty,
              bytes.count <= AgentDesktopScreenshotStreamPolicy.screenshotByteLimit,
              (evidence["bytes"]?.intValue ?? Int64(bytes.count)) == Int64(bytes.count),
              evidenceSha256 == digest(bytes) else {
          return false
        }
      }
    }

    var output = payload.object("output") ?? [:]
    if let screenshot = output.object("screenshot") {
      output["screenshot"] = .object(screenshotMetadata(screenshot, evidenceSha256: evidenceSha256))
    }
    let postScreenshot = payload.object("post_screenshot")
    let outputSha256 = digest([
      "status": .string(status),
      "summary": .string(payload.string("summary")),
      "error": errorValue(payload.object("error")),
      "output": .object(output),
      "post_screenshot": postScreenshot.map { .object(screenshotMetadata($0, evidenceSha256: evidenceSha256)) } ?? .null
    ])
    guard payload.string("output_sha256") == outputSha256 else {
      return false
    }

    let receiptId = digest([
      "task_id": .string(payload.string("task_id")),
      "action_id": .string(payload.string("action_id")),
      "authorization_id": .string(payload.string("authorization_id")),
      "desktop_session_id": .string(payload.string("desktop_session_id")),
      "request_sha256": .string(requestSha256),
      "output_sha256": .string(outputSha256),
      "evidence_sha256": .string(evidenceSha256),
      "completed_at": .int(completedAt)
    ])
    guard payload.string("receipt_id") == receiptId else {
      return false
    }

    let signedFields: AgentMcpJSONObject = [
      "receipt_version": .int(Int64(receiptVersion)),
      "receipt_id": .string(receiptId),
      "task_id": .string(payload.string("task_id")),
      "action_id": .string(payload.string("action_id")),
      "authorization_id": .string(payload.string("authorization_id")),
      "desktop_session_id": .string(payload.string("desktop_session_id")),
      "tool_id": .string(payload.string("tool_id")),
      "status": .string(status),
      "summary": .string(payload.string("summary")),
      "error_code": .string(payload.string("error_code")),
      "error_retryable": .bool(payload.bool("error_retryable")),
      "request_sha256": .string(requestSha256),
      "input_sha256": .string(inputSha256),
      "output_sha256": .string(outputSha256),
      "evidence_sha256": .string(evidenceSha256),
      "controller_app_instance_id": .string(payload.string("controller_app_instance_id")),
      "controller_name": .string(payload.string("controller_name")),
      "controller_platform": .string(payload.string("controller_platform")),
      "controller_fingerprint": .string(controllerFingerprint),
      "started_at": .int(startedAt),
      "completed_at": .int(completedAt),
      "duration_ms": .int(durationMillis),
      "signer_id": .string(signerId),
      "signature_key_id": .string(signatureKeyId)
    ]
    return verifier(
      signerId,
      signatureKeyId,
      Data(AgentMcpJSONCodec.stringify(signedFields).utf8),
      payload.string("signature")
    )
  }

  static func digest(_ object: AgentMcpJSONObject) -> String {
    AgentMcpJSONCodec.sha256(object)
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func screenshotMetadata(
    _ value: AgentMcpJSONObject,
    evidenceSha256: String
  ) -> AgentMcpJSONObject {
    var metadata = value
    metadata.removeValue(forKey: "image_base64")
    metadata["image_sha256"] = .string(evidenceSha256)
    return metadata
  }

  private static func errorValue(_ error: AgentMcpJSONObject?) -> AgentMcpJSONValue {
    guard let error else { return .null }
    return .object([
      "code": .string(error.string("code")),
      "message": .string(error.string("message")),
      "retryable": .bool(error.bool("retryable"))
    ])
  }

  private static func validDigest(_ value: String) -> Bool {
    value.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
  }
}

private enum AgentDesktopControlJSON {
  static func stringArray(
    _ value: AgentMcpJSONValue?,
    maxItems: Int = Int.max,
    maxCharacters: Int = Int.max,
    dropBlank: Bool = false
  ) -> [String] {
    (value?.arrayValue ?? [])
      .prefix(maxItems)
      .compactMap { item -> String? in
        let clipped = String((item.stringValue ?? "").prefix(maxCharacters))
        if dropBlank && clipped.isBlank {
          return nil
        }
        return clipped
      }
  }
}
