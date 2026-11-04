import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIScreenPagePDFImporter: View {
  @Binding var isPresented: Bool
  var requestID: UUID?
  var isPDF: Bool
  var onResult: (UUID?, Bool, Result<[URL], Error>) -> Void

  var body: some View {
    Color.clear.fileImporter(isPresented: $isPresented, allowedContentTypes: isPDF ? [.pdf] : [.item],
      allowsMultipleSelection: false) { [requestID, isPDF] result in onResult(requestID, isPDF, result) }
  }
}

struct GalaxySSIScreenAnalysisLinkPicker: View {
  @Environment(\.dismiss) private var dismiss
  @State private var value = ""
  var t: (String, String) -> String
  var onAdd: (String) -> Void

  private var link: String? {
    let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard input.utf8.count <= 4_096, !input.contains(where: { $0.isWhitespace }),
          let parts = URLComponents(string: input), parts.scheme?.lowercased() == "https",
          parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
          parts.url != nil else { return nil }
    return input
  }

  var body: some View {
    NavigationView {
      Form {
        TextField("https://", text: $value)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("ios.screen-assistant.link-input")
      }
      .navigationTitle(t("galaxyssi.screen_page.link", "Link"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("galaxyssi.common.add", "Add")) {
            if let link { onAdd(link); dismiss() }
          }
          .disabled(link == nil)
        }
      }
    }
    .navigationViewStyle(.stack)
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
    beginScreenSourceFileImport(isPDF: true)
  }

  func beginScreenAnalysisFileImport() {
    beginScreenSourceFileImport(isPDF: false)
  }

  private func beginScreenSourceFileImport(isPDF: Bool) {
    cancelScreenPagePDFImport()
    screenPageImportIsPDF = isPDF
    screenPageImportConversationID = store.activeAgentConversationId
    screenPageImportRequestID = UUID()
    screenPagePickerPresented = true
  }

  func cancelScreenPagePDFImport() {
    screenLinkPickerPresented = false
    screenLinkConversationID = ""
    screenPageImportRequestID = nil
    screenPageImportConversationID = ""
    screenPageImportTask?.cancel()
    screenPageImportTask = nil
    screenPagePickerPresented = false
    screenCaptureSourcePresented = false
  }

  func importScreenAnalysisFile(_ result: Result<[URL], Error>, requestID: UUID?) {
    guard let requestID, requestID == screenPageImportRequestID else { return }
    defer { cancelScreenPagePDFImport() }
    guard !screenAssistantStopping, !screenPageImportConversationID.isEmpty,
          screenPageImportConversationID == store.activeAgentConversationId else { return }
    do {
      guard let url = try result.get().first else { return }
      let attachment = try GalaxySSIAttachmentPayloadBuilder.makeAttachment(from: url)
      appendAttachment(attachment)
      guard attachments.contains(where: { $0.id == attachment.id }) else { return }
      openScreenAnalysisSource()
      screenAssistantAttachmentIDs.insert(attachment.id)
      if draft.isBlank { draft = t("galaxyssi.screen_page.file_prompt", "Analyze this file.") }
    } catch {
      let failure = error as NSError
      if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError {
        attachmentError = error.localizedDescription
      }
    }
  }

  func beginScreenAnalysisLink() {
    cancelScreenPagePDFImport()
    screenLinkConversationID = store.activeAgentConversationId
    screenLinkPickerPresented = !screenLinkConversationID.isEmpty
  }

  func addScreenAnalysisLink(_ link: String) {
    guard !screenAssistantStopping, !screenLinkConversationID.isEmpty,
          screenLinkConversationID == store.activeAgentConversationId else { return }
    openScreenAnalysisSource()
    if draft.isBlank { draft = t("galaxyssi.screen_page.link_prompt", "Analyze this page.") }
    draft += "\n" + link
  }

  private func openScreenAnalysisSource() {
    screenAssistantConversationID = store.activeAgentConversationId
    screenAssistantCompact = true
    screenAssistantCollapsed = false
    screenAssistantRunID = UUID()
    screenAssistantStartedAt = Date()
    screenAssistantOwnedTurns = []
    screenAssistantAttachmentIDs.formIntersection(Set(attachments.map(\.id)))
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
