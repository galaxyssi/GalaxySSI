import Foundation

extension AgentHomeView {
  func installAgentHomeTapBridge() {
    AgentIOSAgentHomeActionBridge.shared.installTapHandler { action in
      applyAgentHomeTapAction(action)
    }
  }

  func installAgentHomeLongPressBridge() {
    AgentIOSAgentHomeActionBridge.shared.installLongPressHandler { action in
      applyAgentHomeLongPressAction(action)
    }
  }

  func installAgentHomeBackBridge() {
    AgentIOSAgentHomeActionBridge.shared.installBackHandler { action in
      applyAgentHomeBackAction(action)
    }
  }

  func applyAgentHomeTapAction(_ action: AgentAction) -> AgentActionResult {
    let bounds = action.parameters["bounds"] ?? ""
    let matchedLabel = action.parameters["matched_label"] ?? ""
    let resolvedBounds = bounds.isEmpty
      ? agentScreenSnapshot.screen.clickableElements.first { $0.label == matchedLabel }?.bounds ?? ""
      : bounds
    let prefix = "logical://AgentHomeView/"
    guard resolvedBounds.hasPrefix(prefix) else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: t(
          "signalasi.agent.tap.unsupported_target",
          "This Agent action does not target a SignalASI home control."
        ),
        metadata: [
          "platform": "ios",
          "surface": "signalasi_agent_home",
          "completion_verified": "false",
          "ios_boundary": "owned_agent_home_only"
        ]
      )
    }
    let targetID = String(resolvedBounds.dropFirst(prefix.count))
    guard !targetID.isEmpty, !targetID.contains("/") else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: t(
          "signalasi.agent.tap.invalid_target",
          "The SignalASI home control target is invalid."
        ),
        metadata: [
          "platform": "ios",
          "surface": "signalasi_agent_home",
          "completion_verified": "false"
        ]
      )
    }

    guard activateAgentHomeControl(targetID) else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: t(
          "signalasi.agent.tap.unknown_target",
          "This SignalASI home control is not available."
        ),
        metadata: [
          "platform": "ios",
          "surface": "signalasi_agent_home",
          "target_id": targetID,
          "completion_verified": "false"
        ]
      )
    }

    actionTrayPresented = false
    return AgentActionResult(
      actionId: action.id,
      success: true,
      message: t(
        "signalasi.agent.tap.completed",
        "SignalASI home control activated."
      ),
      metadata: [
        "platform": "ios",
        "surface": "signalasi_agent_home",
        "target_id": targetID,
        "completion_verified": "true"
      ]
    )
  }

  @discardableResult
  func activateAgentHomeControl(_ targetID: String) -> Bool {
    switch targetID {
    case "new-session":
      createAgentConversation()
    case "sessions":
      agentSessionsShortcutActive = true
    case "scan":
      scanShortcutActive = true
    case "take-photo":
      openCameraAttachmentPicker()
    case "add-photos":
      photoPickerPresented = true
    case "add-file":
      fileImporterPresented = true
    case "permissions":
      agentPermissionsShortcutActive = true
    case "model-selection":
      agentModelSelectionShortcutActive = true
    case "native-tools":
      agentNativeToolsShortcutActive = true
    case "memory":
      agentMemoryShortcutActive = true
    case "knowledge":
      agentKnowledgeShortcutActive = true
    case "screen-context":
      agentScreenContextShortcutActive = true
    case "refresh-screen-context":
      refreshAgentScreenContext()
    case "insights":
      agentInsightsShortcutActive = true
    case "recent-tasks":
      recentTaskForDetails = nil
      recentTasksShortcutActive = true
    case "permission-mode":
      cycleAgentPermissionMode()
    case "task-execution-mode":
      cycleAgentTaskExecutionMode()
    case "high-risk-guard":
      store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
    case "memory-capture":
      store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
    case "execution-paused":
      store.updateAgentSafetySettings { $0.executionPaused.toggle() }
    case "settings", "launch-settings":
      openMainTab(.settings)
    case "messages", "launch-messages":
      openMainTab(.sessions)
    case "contacts", "launch-contacts":
      contactsShortcutActive = true
    case "discover", "launch-discover":
      openMainTab(.discover)
    case "agent", "launch-agent":
      break
    default:
      return false
    }
    return true
  }

  func applyAgentHomeLongPressAction(_ action: AgentAction) -> AgentActionResult {
    let tapResult = applyAgentHomeTapAction(action)
    var metadata = tapResult.metadata
    metadata["interaction"] = "long_press"
    return AgentActionResult(
      actionId: tapResult.actionId,
      success: tapResult.success,
      message: tapResult.success
        ? t("signalasi.agent.long_press.completed", "SignalASI home control long-pressed.")
        : tapResult.message,
      metadata: metadata
    )
  }

  func applyAgentHomeBackAction(_ action: AgentAction) -> AgentActionResult {
    let dismissedSurface: String?
    if actionTrayPresented {
      actionTrayPresented = false
      dismissedSurface = "action_tray"
    } else if scanShortcutActive {
      scanShortcutActive = false
      dismissedSurface = "scan_sheet"
    } else if cameraPickerPresented {
      cameraPickerPresented = false
      dismissedSurface = "camera_sheet"
    } else if photoPickerPresented {
      photoPickerPresented = false
      dismissedSurface = "photo_picker"
    } else if fileImporterPresented {
      fileImporterPresented = false
      dismissedSurface = "file_importer"
    } else if homeActionEditorSelection != nil {
      homeActionEditorSelection = nil
      dismissedSurface = "action_editor"
    } else if !runtimeArtifactError.isEmpty {
      runtimeArtifactError = ""
      dismissedSurface = "artifact_error"
    } else if !runtimeArtifactStatus.isEmpty {
      runtimeArtifactStatus = ""
      dismissedSurface = "artifact_status"
    } else if !richActionStatus.isEmpty {
      richActionStatus = ""
      dismissedSurface = "action_status"
    } else if runtimeArtifactPreview != nil {
      runtimeArtifactPreview = nil
      dismissedSurface = "artifact_preview"
    } else if runtimeArtifactExportPresented {
      runtimeArtifactExportPresented = false
      dismissedSurface = "artifact_exporter"
    } else if publicPageExportPresented {
      publicPageExportPresented = false
      dismissedSurface = "public_page_exporter"
    } else if pendingHighRiskApprovalTask != nil {
      pendingHighRiskApprovalTask = nil
      dismissedSurface = "high_risk_confirmation"
    } else if homeTaskPendingDeletion != nil {
      homeTaskPendingDeletion = nil
      dismissedSurface = "task_deletion_confirmation"
    } else {
      dismissedSurface = nil
    }

    guard let dismissedSurface else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: t(
          "signalasi.agent.back.nothing_to_dismiss",
          "There is no open SignalASI Agent surface to dismiss."
        ),
        metadata: [
          "platform": "ios",
          "surface": "signalasi_agent_home",
          "completion_verified": "false"
        ]
      )
    }
    return AgentActionResult(
      actionId: action.id,
      success: true,
      message: t(
        "signalasi.agent.back.completed",
        "SignalASI Agent surface dismissed."
      ),
      metadata: [
        "platform": "ios",
        "surface": "signalasi_agent_home",
        "dismissed_surface": dismissedSurface,
        "completion_verified": "true"
      ]
    )
  }
}
