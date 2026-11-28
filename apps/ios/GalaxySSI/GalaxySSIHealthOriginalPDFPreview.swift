import SwiftUI

@MainActor
struct GalaxySSIHealthOriginalPDFPreview: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let data: Data
  let name: String
  @State private var index = 0
  @State private var count = 0
  @State private var image: CGImage?
  @State private var password: String?
  @State private var status = Status.idle
  @State private var requestID: UUID?
  @State private var task: Task<Void, Never>?
  private enum Status { case idle, working, locked, incorrect, failed, cancelled }

  var body: some View {
    Group {
      if scene == .active {
        if status == .locked || status == .incorrect {
          GalaxySSIHealthPDFPasswordForm(failed: status == .incorrect) {
            guard scene == .active else { return }
            password = $0
            render()
          }
        } else {
          VStack {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit().accessibilityLabel(Text(name)) }
            if status == .working {
              ProgressView(t("preview_working", "Opening PDF"))
              Button(t("preview_cancel", "Cancel")) { clear(); status = .cancelled }
            }
            if status == .failed || status == .cancelled {
              Text(status == .failed ? t("preview_failed", "The PDF page could not be opened.") : t("preview_cancelled", "PDF preview cancelled"))
              Button(t("preview_retry", "Retry"), action: render)
            }
            if count > 0 {
              HStack {
                Button { index -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                  .disabled(index == 0 || status == .working)
                  .accessibilityLabel(Text(t("previous_page", "Previous page")))
                Text(String(format: t("page", "Page %lld of %lld"), Int64(index + 1), Int64(count)))
                Button { index += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                  .disabled(index >= count - 1 || status == .working)
                  .accessibilityLabel(Text(t("next_page", "Next page")))
              }
            }
          }
        }
      }
    }
    .privacySensitive()
    .onAppear(perform: render)
    .onChange(of: index) { _ in render() }
    .onChange(of: scene) { if $0 == .active { render() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear() }
    .onDisappear(perform: clear)
  }

  private func render() {
    guard scene == .active else { return }
    requestID = nil
    task?.cancel()
    image = nil
    let token = UUID(), page = index, credential = password, input = data
    requestID = token
    status = .working
    task = Task {
      let worker = Task.detached(priority: .userInitiated) {
        try GalaxySSIHealthPDFText.previewPage(input, page: page, password: credential)
      }
      do {
        let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, requestID == token, scene == .active else { return }
        image = result.image; count = result.pages; status = .idle
      } catch {
        guard !Task.isCancelled, requestID == token, scene == .active else { return }
        switch error {
        case GalaxySSIHealthPDFText.Failure.locked: password = nil; status = .locked
        case GalaxySSIHealthPDFText.Failure.incorrectPassword: password = nil; status = .incorrect
        default: password = nil; status = .failed
        }
      }
      task = nil
    }
  }

  private func clear() {
    requestID = nil
    task?.cancel(); task = nil
    password = nil; image = nil; count = 0; status = .idle
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.originals." + key, fallback: fallback, language: language)
  }
}
