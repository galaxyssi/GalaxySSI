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
  @State private var pdfTask: Task<Void, Never>?
  @State private var pdfStatus = ""
  var t: (String, String) -> String
  var weChatOnly: Bool
  var onAdd: (String) -> Void
  @State private var weChatBrowserPresented = false

  private var link: String? {
    Self.validatedLink(value, weChatOnly: weChatOnly)
  }

  static func validatedLink(_ value: String, weChatOnly: Bool) -> String? {
    let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard input.utf8.count <= 4_096, !input.contains(where: { $0.isWhitespace }),
          let parts = URLComponents(string: input), parts.scheme?.lowercased() == "https",
          parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
          parts.url != nil else { return nil }
    if weChatOnly {
      guard parts.host?.lowercased() == "mp.weixin.qq.com",
            parts.port == nil || parts.port == 443,
            parts.path == "/s" || (parts.path.hasPrefix("/s/") && parts.path.count > 3)
      else { return nil }
    }
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
        if GalaxySSIWeChatBrowserSession.articleURL(value) != nil {
          Button {
            weChatBrowserPresented = true
          } label: {
            Label(t("galaxyssi.screen_page.wechat_browser", "WeChat Article Browser"), systemImage: "safari")
          }
        }
        if let article = AgentIOSWeChatArticlePDF.articleURL(value) {
          Button {
            saveArticle(article)
          } label: {
            Label(t("galaxyssi.screen_page.wechat_pdf", "Save WeChat Article PDF"), systemImage: "arrow.down.doc")
          }
          .disabled(pdfTask != nil)
          if pdfTask != nil { ProgressView() }
          if !pdfStatus.isEmpty { Text(pdfStatus).font(.footnote).foregroundColor(.secondary) }
        }
        if weChatOnly {
          if #available(iOS 16.0, *) {
            PasteButton(payloadType: String.self) { values in
              if let first = values.first { value = first }
            }
          }
          if !value.isEmpty, link == nil {
            Text(t("galaxyssi.screen_page.wechat_invalid", "Enter a valid WeChat public article link."))
              .foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle(weChatOnly
        ? t("galaxyssi.screen_page.wechat_link", "WeChat Article Link")
        : t("galaxyssi.screen_page.link", "Link"))
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
    .sheet(isPresented: $weChatBrowserPresented) {
      if let article = GalaxySSIWeChatBrowserSession.articleURL(value) {
        GalaxySSIWeChatArticleBrowser(url: article, t: t)
      }
    }
    .onDisappear { pdfTask?.cancel() }
  }

  private func saveArticle(_ url: URL) {
    guard pdfTask == nil else { return }
    pdfStatus = ""
    let missingImage = t("galaxyssi.screen_page.wechat_pdf_image", "[Image unavailable]")
    let worker = Task.detached(priority: .userInitiated) {
      try AgentIOSWeChatArticlePDF.save(url: url, missingImage: missingImage)
    }
    pdfTask = Task { @MainActor in
      defer { pdfTask = nil }
      do {
        let (file, missing) = try await withTaskCancellationHandler(operation: { try await worker.value },
          onCancel: { worker.cancel() })
        guard !Task.isCancelled else { return }
        pdfStatus = String(format: t("galaxyssi.screen_page.wechat_pdf_saved",
          "Saved in Files: GalaxySSI / Downloads / GongZhongHao / %@"), file.lastPathComponent)
        if missing > 0 {
          pdfStatus += "\n" + String(format: t("galaxyssi.screen_page.wechat_pdf_missing",
            "%d images could not be saved."), missing)
        }
      } catch {
        guard !Task.isCancelled else { return }
        pdfStatus = t("galaxyssi.screen_page.wechat_pdf_failed",
          "Could not save this article. Open it in WeChat and check whether verification is required.")
      }
    }
  }
}

extension AgentHomeView {
  var screenAssistantHasActiveWork: Bool {
    guard let phase = screenAssistantBubblePhase else { return false }
    return [.observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused].contains(phase)
  }

  func beginScreenAssistantScreenshot() {
    cancelScreenPagePDFImport()
    screenshotPickerPresented = true
  }

  func presentScreenCaptureSources() {
    actionTrayPresented = false
    guard !screenAssistantStopping else { return }
    if screenAssistantHasActiveWork {
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
    beginScreenAnalysisLink(weChatOnly: false)
  }

  func beginScreenAnalysisLink(weChatOnly: Bool) {
    cancelScreenPagePDFImport()
    screenLinkWeChatOnly = weChatOnly
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
        let added = String(format: t("galaxyssi.screen_page.added", "%d pages added"), page.pageCount)
        if page.truncated {
          attachmentError = t("galaxyssi.screen_page.truncated", "Text extraction was limited; the original PDF is included.")
        } else if page.emptyTextPages > 0 {
          attachmentError = t("galaxyssi.screen_page.image_pages", "Some pages have no selectable text; the original PDF is included.")
        }
        let pdf = page.attachments.first(where: { $0.mimeType == "application/pdf" })?.data
        let captureID = page.captureID
        let export = Task.detached(priority: .utility) {
          guard let pdf else { throw AgentIOSScreenPagePDFError.invalidDocument }
          return try AgentIOSScreenPagePDFDownloads.save(pdf: pdf, captureID: captureID)
        }
        let saved = await withTaskCancellationHandler(operation: { try? await export.value },
          onCancel: { export.cancel() })
        guard !Task.isCancelled, screenPageImportRequestID == requestID,
              screenAssistantRunID == runID, scenePhase == .active,
              store.activeAgentConversationId == conversationID else { return }
        let status: String
        if let saved {
          status = String(format: t("galaxyssi.screen_page.pdf_saved",
            "Kept in GalaxySSI: %@"), saved.lastPathComponent)
        } else {
          status = t("galaxyssi.screen_page.pdf_save_failed",
            "Could not keep a private copy. The original PDF is still attached.")
        }
        richActionStatus = added + "\n" + status
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
