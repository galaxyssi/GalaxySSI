import SwiftUI

@MainActor
struct GalaxySSIPublicNewsBodyView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var store: GalaxySSIStore
  @ObservedObject private var playback = PublicNewsSpeechPlayback.shared
  let article: PublicNewsArticle
  let retainedArticleIDs: Set<String>
  let rememberCover: (URL) -> Void

  @State private var checkpoint: PublicNewsBodyCheckpoint?
  @State private var request: Request?
  @State private var failure: Failure?
  @State private var showChinese = false

  private enum Operation: Equatable { case fetch, translate }
  private struct Request: Equatable {
    let id = UUID()
    let operation: Operation
  }
  private enum Failure { case original, modelUnavailable, translation }

  var body: some View {
    if PublicNewsArticleBody.supports(article.url) {
      VStack(alignment: .leading, spacing: 12) {
        Divider()
        if let checkpoint {
          controls(checkpoint)
        } else {
          Button(t("public_news_load_body", "Load original article")) { begin(.fetch) }
            .disabled(request != nil || scenePhase != .active)
        }
        if let request {
          HStack(spacing: 8) {
            ProgressView()
            Text(progressText(request.operation)).font(.callout).foregroundColor(.secondary)
            Spacer()
            Button(t("common_cancel", "Cancel")) { self.request = nil }
          }
        }
        if let failure {
          Text(failureText(failure)).font(.callout).foregroundColor(.secondary)
        }
        if let checkpoint {
          speechControls(checkpoint)
          GalaxySSIPublicNewsDocumentView(checkpoint: checkpoint, articleURL: article.url, showChinese: showChinese,
            playFromParagraph: { index in play(checkpoint, paragraph: index) })
        }
      }
      .task(id: article.id) {
        let saved = await PublicNewsBodyStore.shared.load(article.id)
        guard !Task.isCancelled, checkpoint == nil, request == nil else { return }
        checkpoint = saved
        showChinese = saved?.completed != nil
        if let cover = saved?.source.presentation?.cover { rememberCover(cover) }
      }
      .task(id: request) {
        if let request { await run(request) }
      }
      .onChange(of: scenePhase) { if $0 != .active { request = nil } }
    }
  }

  private var speechItem: PublicNewsSpeechBookmark.Item {
    .init(articleKey: PublicNewsSpeechBookmark.key(for: article.id), edition: showChinese ? .chinese : .original)
  }

  @ViewBuilder
  private func speechControls(_ checkpoint: PublicNewsBodyCheckpoint) -> some View {
    if playback.queue.current == speechItem {
      GalaxySSIPublicNewsSpeechControls(playback: playback)
      if playback.queue.phase == .failed {
        Text(t("public_news_speech_failed", "Could not read the downloaded article."))
          .font(.footnote)
          .foregroundColor(.secondary)
      }
    } else {
      Button { play(checkpoint, paragraph: 0) } label: {
        Label(t("public_news_speech_read", "Read aloud"), systemImage: "speaker.wave.2")
          .frame(minHeight: 44)
      }
      .disabled(!store.voiceSettings.textToSpeechEnabled || scenePhase != .active)
    }
  }

  private func play(_ checkpoint: PublicNewsBodyCheckpoint, paragraph: Int) {
    guard scenePhase == .active, let document = PublicNewsSpeechDocument(checkpoint: checkpoint, edition: speechItem.edition),
          document.paragraphs.indices.contains(paragraph) else { return }
    playback.play([speechItem], paragraph: paragraph, documentKey: document.key,
      settings: store.voiceSettings, languagePolicy: store.languagePolicy)
  }

  @ViewBuilder
  private func controls(_ checkpoint: PublicNewsBodyCheckpoint) -> some View {
    if checkpoint.completed != nil {
      Picker(t("public_news_body_language", "Article language"), selection: $showChinese) {
        Text(t("public_news_body_original", "Original")).tag(false)
        Text(t("public_news_body_chinese", "Chinese")).tag(true)
      }
      .pickerStyle(.segmented)
    } else {
      let partiallyTranslated = checkpoint.translated.contains { $0 != nil }
      Button(partiallyTranslated ? t("public_news_resume_translation", "Resume Chinese translation") :
        t("public_news_translate_body", "Translate to Chinese")) { begin(.translate) }
        .disabled(request != nil || scenePhase != .active)
    }
    Button {
      begin(.fetch)
    } label: {
      Label(t("public_news_refresh_body", "Refresh original article"), systemImage: "arrow.clockwise")
    }
    .disabled(request != nil || scenePhase != .active)
  }

  private func begin(_ operation: Operation) {
    guard request == nil, scenePhase == .active else { return }
    failure = nil
    request = Request(operation: operation)
  }

  private func run(_ job: Request) async {
    do {
      let next: PublicNewsBodyCheckpoint
      switch job.operation {
      case .fetch:
        let original = try await PublicNewsArticleBody.load(article.url)
        next = try await PublicNewsBodyStore.shared.install(original, articleID: article.id, retaining: retainedArticleIDs)
      case .translate:
        guard let checkpoint else { throw PublicNewsArticleBodyError.incompleteSource }
        next = try await PublicNewsTranslation.run(checkpoint) { update in
          guard request == job, !Task.isCancelled else { return }
          self.checkpoint = update
        }
      }
      guard !Task.isCancelled, request == job else { return }
      checkpoint = next
      showChinese = next.completed != nil
      if let cover = next.source.presentation?.cover { rememberCover(cover) }
    } catch {
      guard !Task.isCancelled, request == job else { return }
      if case PublicNewsArticleBodyError.modelUnavailable = error { failure = .modelUnavailable }
      else { failure = job.operation == .fetch ? .original : .translation }
    }
    if request == job { request = nil }
  }

  private func progressText(_ operation: Operation) -> String {
    switch operation {
    case .fetch: return t("public_news_fetching_body", "Loading original article")
    case .translate:
      let current = checkpoint?.translated.compactMap { $0 }.count ?? 0
      let total = checkpoint?.segments.count ?? 0
      return String(format: t("public_news_translate_progress", "Translating %d / %d"), current, total)
    }
  }

  private func failureText(_ value: Failure) -> String {
    switch value {
    case .original: return t("public_news_body_failed", "The complete original article could not be extracted.")
    case .modelUnavailable: return t("public_news_translation_model", "An enabled, installed local model is required.")
    case .translation: return t("public_news_translation_failed", "Translation stopped. Validated progress was kept.")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
