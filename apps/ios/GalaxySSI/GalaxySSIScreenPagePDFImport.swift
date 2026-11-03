import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIScreenPagePDFImporter: View {
  @Binding var isPresented: Bool
  var requestID: UUID?
  var onResult: (UUID?, Result<[URL], Error>) -> Void

  var body: some View {
    Color.clear.fileImporter(isPresented: $isPresented, allowedContentTypes: [.pdf],
      allowsMultipleSelection: false) { [requestID] result in onResult(requestID, result) }
  }
}

extension AgentHomeView {
  func presentScreenCaptureSources() {
    actionTrayPresented = false
    guard !screenAssistantStopping else { return }
    if let phase = screenAssistantBubblePhase,
       [.observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused].contains(phase) {
      screenAssistantCollapsed = false
      return
    }
    screenCaptureSourcePresented = true
  }

  func beginScreenPagePDFImport() {
    cancelScreenPagePDFImport()
    screenPageImportConversationID = store.activeAgentConversationId
    screenPageImportRequestID = UUID()
    screenPagePickerPresented = true
  }

  func cancelScreenPagePDFImport() {
    screenPageImportRequestID = nil
    screenPageImportConversationID = ""
    screenPageImportTask?.cancel()
    screenPageImportTask = nil
    screenPagePickerPresented = false
    screenCaptureSourcePresented = false
  }

  func importScreenPagePDF(_ result: Result<[URL], Error>, requestID: UUID?) {
    guard let requestID, requestID == screenPageImportRequestID else { return }
    if case .failure(let error) = result {
      cancelScreenPagePDFImport()
      let failure = error as NSError
      if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError {
        attachmentError = t("galaxyssi.screen_page.failed", "The page PDF could not be imported.")
      }
      return
    }
    guard case .success(let urls) = result, let url = urls.first,
          !screenPageImportConversationID.isEmpty,
          screenPageImportConversationID == store.activeAgentConversationId,
          !screenAssistantStopping else { cancelScreenPagePDFImport(); return }
    let conversationID = screenPageImportConversationID
    screenAssistantConversationID = conversationID
    screenAssistantCompact = true
    screenAssistantCollapsed = false
    screenAssistantRunID = UUID()
    screenAssistantStartedAt = Date()
    screenAssistantOwnedTurns = []
    let runID = screenAssistantRunID
    richActionStatus = t("galaxyssi.screen_page.collecting", "Collecting page...")
    let worker = Task.detached(priority: .userInitiated) { try AgentIOSScreenPagePDFCapture.collect(url: url) }
    screenPageImportTask = Task { @MainActor in
      defer {
        worker.cancel()
        if screenPageImportRequestID == requestID { screenPageImportTask = nil }
      }
      do {
        let page = try await withTaskCancellationHandler(operation: { try await worker.value },
          onCancel: { worker.cancel() })
        guard !Task.isCancelled, screenPageImportRequestID == requestID,
              screenAssistantRunID == runID, scenePhase == .active,
              store.activeAgentConversationId == conversationID else { return }
        let previous = attachments
        for attachment in page.attachments { appendAttachment(attachment) }
        guard page.attachments.allSatisfy({ item in attachments.contains { $0.id == item.id } }) else {
          attachments = previous
          return
        }
        screenAssistantAttachmentIDs = screenAssistantAttachmentIDs.intersection(Set(attachments.map(\.id)))
          .union(page.attachments.map(\.id))
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          draft = t("galaxyssi.screen_page.prompt", "Analyze this captured page.")
        }
        richActionStatus = String(format: t("galaxyssi.screen_page.added", "%d pages added"), page.pageCount)
        if page.truncated {
          attachmentError = t("galaxyssi.screen_page.truncated", "Text extraction was limited; the original PDF is included.")
        } else if page.emptyTextPages > 0 {
          attachmentError = t("galaxyssi.screen_page.image_pages", "Some pages have no selectable text; the original PDF is included.")
        }
      } catch {
        guard !Task.isCancelled, screenPageImportRequestID == requestID else { return }
        let key: String
        let fallback: String
        switch error {
        case AgentIOSScreenPagePDFError.protectedDocument:
          key = "galaxyssi.screen_page.protected"
          fallback = "Encrypted or copy-protected PDFs are not supported."
        case AgentIOSScreenPagePDFError.sizeLimit, AgentIOSScreenPagePDFError.pageLimit:
          key = "galaxyssi.screen_page.limit"
          fallback = "The PDF exceeds 32 MB or 256 pages."
        default:
          key = "galaxyssi.screen_page.failed"
          fallback = "The page PDF could not be imported."
        }
        attachmentError = t(key, fallback)
        richActionStatus = ""
      }
    }
  }
}
