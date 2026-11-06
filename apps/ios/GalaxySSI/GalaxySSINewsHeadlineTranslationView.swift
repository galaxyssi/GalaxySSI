import SwiftUI
#if canImport(Translation)
import Translation
#endif

@MainActor
struct GalaxySSINewsHeadlineTranslationView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var archive: PublicNewsArchive
  @StateObject private var work = NewsHeadlineTranslationBatch()
  @State private var localRequest: UUID?

  var body: some View {
    Form {
      #if canImport(Translation)
      if #available(iOS 18.0, *) {
        AppleNewsHeadlineTranslationButton(archive: archive, work: work)
      } else {
        localButton
      }
      #else
      localButton
      #endif

      if work.running {
        ProgressView(value: Double(work.processed), total: Double(max(1, work.total)))
      }
      if work.deferred {
        Text(t("public_news_headline_deferred", "Translation is paused while the device is hot, low on battery, or in Low Power Mode."))
          .foregroundColor(.secondary)
      } else if let result = work.result {
        Text(String(format: t("public_news_headline_translation_result", "%d translated, %d unchanged"), result.saved, result.skipped))
      }
    }
    .navigationTitle(t("public_news_headline_translate", "Translate headlines"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(t("common_close", "Close")) { dismiss() }
      }
    }
    .task(id: localRequest) {
      guard localRequest != nil else { return }
      await work.run(archive: archive, system: nil)
    }
    .onChange(of: scenePhase) { phase in
      if phase == .background { work.cancel() }
    }
    .onDisappear { work.cancel() }
  }

  private var localButton: some View {
    Button(t("public_news_headline_translate_next", "Translate next headlines")) { localRequest = UUID() }
      .disabled(work.running)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
private final class NewsHeadlineTranslationBatch: ObservableObject {
  struct Result { let saved: Int; let skipped: Int }
  @Published private(set) var running = false
  @Published private(set) var processed = 0
  @Published private(set) var total = 0
  @Published private(set) var result: Result?
  @Published private(set) var deferred = false
  private var generation = UUID()
  private var attempted = [String: String]()

  func run(archive: PublicNewsArchive, system: ((String) async throws -> String)? = nil) async {
    guard !running, !Task.isCancelled else { return }
    deferred = !PublicNewsHeadlineTranslator.deviceAllowsTranslation
    guard !deferred else { return }
    let operation = UUID()
    generation = operation
    let available = archive.eligibleArticles
    let fresh = available.filter { attempted[$0.id] != $0.title }
    var candidates = PublicNewsHeadlineTranslator.candidates(fresh)
    if candidates.isEmpty {
      attempted.removeAll(keepingCapacity: true)
      candidates = PublicNewsHeadlineTranslator.candidates(available)
    }
    running = true
    processed = 0
    total = candidates.count
    result = nil
    var saved = 0
    defer {
      if generation == operation {
        running = false
        result = Result(saved: saved, skipped: processed - saved)
      }
    }
    for article in candidates {
      guard !Task.isCancelled, generation == operation else { return }
      let load = AgentIOSBackgroundLoad.current()
      guard load.deferSeconds == 0 else { deferred = true; return }
      if processed > 0, load.spacing > 1 {
        do { try await Task.sleep(nanoseconds: UInt64(load.spacing * 1_000_000_000)) }
        catch { return }
        guard generation == operation, !Task.isCancelled else { return }
        guard PublicNewsHeadlineTranslator.deviceAllowsTranslation else { deferred = true; return }
      }
      var provider = PublicNewsHeadlineTranslation.Provider.apple
      var translation: String?
      if let system, let output = try? await system(article.title) {
        translation = PublicNewsHeadlineTranslator.validate(output, source: article.title)
      }
      guard !Task.isCancelled, generation == operation else { return }
      if translation == nil {
        provider = .localModel
        translation = try? await PublicNewsHeadlineTranslator.translateWithLocalModel(article.title)
      }
      guard !Task.isCancelled, generation == operation else { return }
      guard PublicNewsHeadlineTranslator.deviceAllowsTranslation else { deferred = true; return }
      if let translation,
         archive.storeHeadline(translation, for: article.id, source: article.title, provider: provider) { saved += 1 }
      attempted[article.id] = article.title
      processed += 1
    }
  }

  func cancel() {
    generation = UUID()
    running = false
  }
}

#if canImport(Translation)
@available(iOS 18.0, *)
@MainActor
private struct AppleNewsHeadlineTranslationButton: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var archive: PublicNewsArchive
  @ObservedObject var work: NewsHeadlineTranslationBatch
  @State private var configuration: TranslationSession.Configuration?

  var body: some View {
    Button(GalaxySSILocalization.string("public_news_headline_translate_next",
      fallback: "Translate next headlines", language: language)) {
      configuration = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "zh-Hans"))
    }
    .disabled(work.running || configuration != nil)
    .translationTask(configuration) { session in
      await work.run(archive: archive) { text in
        try await session.translate(text).targetText
      }
      await finish()
    }
    .onChange(of: scenePhase) { phase in
      if phase == .background { configuration = nil }
    }
  }

  private func finish() { configuration = nil }
}
#endif
