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
    guard !normalizedIDs.isEmpty else {
      scanStatus = t(
        "signalasi.agent.scan.no_agent",
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
              "signalasi.agent.scan.selected",
              "Agent added and selected for this session."
            )
            scanStatusIsError = false
            return
          }
        }
      }
      guard scanSelectionRequestID == requestID else { return }
      scanStatus = t(
        "signalasi.agent.scan.not_ready",
        "Agent was added, but is not ready to communicate yet. Check the Agent connection in Contacts."
      )
      scanStatusIsError = true
    }
  }

  private func scannedAgentContact(for requestedID: String) -> SignalASIContact? {
    let normalizedID = requestedID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedID.isEmpty else { return nil }
    if let direct = store.contact(id: normalizedID), direct.type == "agent" {
      return direct
    }

    let parts = normalizedID.split(separator: ":", omittingEmptySubsequences: true)
    let requestedAgentID = parts.last.map(String.init) ?? normalizedID
    let requestedDesktopID = parts.count > 1
      ? parts.dropLast().map(String.init).joined(separator: ":")
      : ""
    return store.contacts.first { contact in
      guard contact.type == "agent", !contact.deleted else { return false }
      let knownIDs = [
        contact.id,
        contact.signalASIId,
        contact.agentId ?? "",
        contact.connectorAgentId
      ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if knownIDs.contains(normalizedID) {
        return true
      }
      let knownAgentIDs = [contact.agentId ?? "", contact.connectorAgentId]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard !requestedDesktopID.isEmpty else {
        return knownAgentIDs.contains(requestedAgentID)
      }
      return contact.desktopId == requestedDesktopID &&
        knownAgentIDs.contains(requestedAgentID)
    }
  }

  private func focusScannedAgentIfAvailable(_ targetID: String) -> Bool {
    guard let target = scannedAgentContact(for: targetID) else {
      return false
    }
    let conversationId = store.activeAgentConversationId
    AgentModelSelectionSettings.selectManual(
      for: conversationId,
      targetId: target.id,
      modelId: target.selectedCloudModel?.modelId ?? "",
      displayName: target.displayName
    )
    store.setAgentSessionSelectedModelOrAgent(
      id: conversationId,
      label: target.displayName.ifBlank(target.name).ifBlank(target.id)
    )
    modelSelection = AgentModelSelectionSettings.selection(for: conversationId)
    return true
  }

  func ensureActiveAgentSession() {
    if let session = activeAgentSession {
      if session.status == .archived {
        _ = store.switchAgentSession(session.id)
      }
      return
    }
    _ = store.createAgentSession(title: t("signalasi.agent.session.new", "New session"))
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
            attachmentError = t("signalasi.scanner.camera_access_required", "Camera access is required to scan SignalASI QR codes.")
          }
        }
      }
    case .denied, .restricted:
      attachmentError = t("signalasi.scanner.camera_access_required", "Camera access is required to scan SignalASI QR codes.")
    @unknown default:
      cameraPickerPresented = true
    }
  }

  func attachmentLabel(for values: [SignalASIDraftAttachment]) -> String {
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
      let attachment = try SignalASIAttachmentPayloadBuilder.makeAttachment(from: url)
      appendAttachment(attachment)
    } catch {
      attachmentError = error.localizedDescription
    }
  }

  func appendAttachment(_ attachment: SignalASIDraftAttachment) {
    guard SignalASIAttachmentPayloadBuilder.accepted(attachment, existing: attachments) else {
      attachmentError = t("agent_attachment_rejected", "Some attachments were skipped. You can add up to 10 files, 64 MB each.")
      return
    }
    attachments.append(attachment)
    attachmentError = ""
  }
}
