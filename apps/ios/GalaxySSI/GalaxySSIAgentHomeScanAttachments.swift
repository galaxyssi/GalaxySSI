import AVFoundation
import UIKit

extension AgentHomeView {
  func focusScannedAgents(_ targetIDs: [String]) {
    // A later scan must take precedence over delayed contact/capability refreshes from an earlier one.
    let requestID = UUID()
    scanSelectionRequestID = requestID
    let normalizedIDs = targetIDs
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    pendingScannedAgentIDs = normalizedIDs
    guard !normalizedIDs.isEmpty else {
      scanStatus = t(
        "galaxyssi.agent.scan.no_agent",
        "The scanned result did not contain an Agent."
      )
      scanStatusIsError = true
      return
    }

    Task { @MainActor in
      let retryOffsets: [UInt64] = [0, 300_000_000, 900_000_000, 1_800_000_000, 3_000_000_000, 5_000_000_000]
      var priorOffset: UInt64 = 0
      for offset in retryOffsets {
        let delay = offset - priorOffset
        if delay > 0 {
          try? await Task.sleep(nanoseconds: delay)
        }
        priorOffset = offset
        guard scanSelectionRequestID == requestID else { return }
        for targetID in normalizedIDs {
          if focusScannedAgentIfAvailable(targetID) {
            guard scanSelectionRequestID == requestID else { return }
            scanStatus = t(
              "galaxyssi.agent.scan.selected",
              "Agent added and selected for this session."
            )
            scanStatusIsError = false
            pendingScannedAgentIDs = []
            return
          }
        }
      }
      guard scanSelectionRequestID == requestID else { return }
      pendingScannedAgentIDs = []
      scanStatus = t(
        "galaxyssi.agent.scan.not_ready",
        "Agent was added, but is not ready to communicate yet. Check the Agent connection in Contacts."
      )
      scanStatusIsError = true
    }
  }

  func retryPendingScannedAgentSelection() {
    guard !pendingScannedAgentIDs.isEmpty else { return }
    focusScannedAgents(pendingScannedAgentIDs)
  }

  private func focusScannedAgentIfAvailable(_ targetID: String) -> Bool {
    guard let conversation = ScannedAgentConversationRouter.open(
      targetIDs: [targetID],
      store: store,
      title: t("galaxyssi.agent_session.new", "New session")
    ) else { return false }
    modelSelection = AgentModelSelectionSettings.selection(for: conversation.id)
    return modelSelection.mode == .manual
  }

  func ensureActiveAgentSession() {
    if let session = activeAgentSession {
      if session.status == .archived {
        _ = store.switchAgentSession(session.id)
      }
      return
    }
    _ = store.createAgentSession(title: t("galaxyssi.agent.session.new", "New session"))
  }

  func openCameraAttachmentPicker() {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      attachmentError = t("agent_attachment_camera_unavailable", "Camera is unavailable")
      return
    }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      cameraPickerPresented = true
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          if granted {
            cameraPickerPresented = true
          } else {
            attachmentError = t("galaxyssi.scanner.camera_access_required", "Camera access is required to scan GalaxySSI QR codes.")
          }
        }
      }
    case .denied, .restricted:
      attachmentError = t("galaxyssi.scanner.camera_access_required", "Camera access is required to scan GalaxySSI QR codes.")
    @unknown default:
      cameraPickerPresented = true
    }
  }

  func attachmentLabel(for values: [GalaxySSIDraftAttachment]) -> String {
    switch values.count {
    case 0:
      return ""
    case 1:
      return values[0].label
    default:
      return String(format: t("agent_attachment_count", "%d attachments"), values.count)
    }
  }

  func addAttachment(url: URL) {
    do {
      let attachment = try GalaxySSIAttachmentPayloadBuilder.makeAttachment(from: url)
      appendAttachment(attachment)
    } catch {
      attachmentError = error.localizedDescription
    }
  }

  func appendAttachment(_ attachment: GalaxySSIDraftAttachment) {
    guard GalaxySSIAttachmentPayloadBuilder.accepted(attachment, existing: attachments) else {
      attachmentError = t("agent_attachment_rejected", "Some attachments were skipped. You can add up to 10 files, 64 MB each.")
      return
    }
    attachments.append(attachment)
    attachmentError = ""
  }
}
