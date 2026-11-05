import SwiftUI

@MainActor
struct GalaxySSIPublicNewsBacklogView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var archive: PublicNewsArchive
  @StateObject private var worker = PublicNewsBacklogWorker.shared

  var body: some View {
    Form {
      Section {
        count(t("public_news_backlog_ready", "Ready in Chinese"), worker.counts.ready)
        count(t("public_news_backlog_waiting", "Waiting"), worker.counts.waiting)
        count(t("public_news_backlog_processing", "Processing"), worker.counts.processing)
        count(t("public_news_backlog_retry", "Retry later"), worker.counts.retry)
      }
      Section {
        if worker.running {
          ProgressView()
          Button(t("common_cancel", "Cancel"), action: worker.cancel)
        } else {
          Button(t("public_news_backlog_start", "Prepare a batch")) { worker.start(archive) }
            .disabled(scenePhase != .active)
        }
        if worker.stoppedForResources {
          Text(t("public_news_backlog_resources", "Processing paused. Check device power, temperature, or local model availability."))
            .foregroundColor(.secondary)
        }
        if worker.storageFailed {
          Text(t("public_news_backlog_error", "The article processing queue could not be saved or loaded."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("public_news_backlog_title", "Article processing"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(t("common_close", "Close")) { dismiss() }
      }
    }
    .task(id: worker.running) { await worker.updateCounts(archive) }
    .onChange(of: scenePhase) { if $0 == .background { worker.cancel() } }
    .onDisappear { worker.cancel() }
  }

  private func count(_ label: String, _ value: Int) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value.formatted()).monospacedDigit().foregroundColor(.secondary)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
