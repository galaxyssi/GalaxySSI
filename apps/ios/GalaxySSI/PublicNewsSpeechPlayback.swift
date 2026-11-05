import Combine
import UIKit

@MainActor
final class PublicNewsSpeechPlayback: ObservableObject {
  static let shared = PublicNewsSpeechPlayback()

  @Published private(set) var queue: PublicNewsSpeechQueue
  @Published private(set) var controlsVisible = false
  var appControlState: String {
    switch queue.phase {
    case .stopped: return "stopped"
    case .paused: return "paused"
    case .loading: return "loading"
    case .playing: return "playing"
    case .failed: return "failed"
    case .finished: return "finished"
    }
  }
  private let bookmarks: PublicNewsSpeechBookmarkStore
  private let media = AppSpokenMediaSession.shared
  private lazy var speech = VoiceProgressiveReplySpeechService()
  private var loadTask: Task<Void, Never>?
  private var speechStarted = false
  private var settings = VoiceSettings.default
  private var languagePolicy = LanguagePolicySettings.default

  init(bookmarks: PublicNewsSpeechBookmarkStore = PublicNewsSpeechBookmarkStore()) {
    self.bookmarks = bookmarks
    queue = PublicNewsSpeechQueue(bookmark: bookmarks.load())
  }

  func play(
    _ items: [PublicNewsSpeechBookmark.Item], paragraph: Int = 0, documentKey: String? = nil,
    settings: VoiceSettings, languagePolicy: LanguagePolicySettings
  ) {
    guard UIApplication.shared.applicationState == .active, settings.textToSpeechEnabled else { return }
    guard queue.replace(items, paragraph: paragraph, documentKey: documentKey) else { return }
    cancelWork()
    self.settings = settings
    self.languagePolicy = languagePolicy
    controlsVisible = true
    persist()
    resume()
  }

  func resume(settings: VoiceSettings, languagePolicy: LanguagePolicySettings) {
    guard settings.textToSpeechEnabled else { return }
    self.settings = settings
    self.languagePolicy = languagePolicy
    if queue.current != nil { controlsVisible = true }
    resume()
  }

  private func resume() {
    guard settings.textToSpeechEnabled, UIApplication.shared.applicationState == .active || media.owns(self),
          let item = queue.current, let token = queue.resume() else { return }
    media.reserve(self, controls: .init(
      title: GalaxySSILocalization.string("public_news_speech_title", fallback: "News reading"),
      resume: { [weak self] in self?.resume() },
      pause: { [weak self] in self?.pause() },
      stop: { [weak self] in self?.stop() },
      relinquish: { [weak self] in self?.pause(relinquish: true) },
      next: { [weak self] in self?.next() }
    ))
    loadTask = Task { [weak self] in
      let document = await Task.detached(priority: .userInitiated) {
        PublicNewsBodyStore.shared.speechDocument(for: item)
      }.value
      guard let self, !Task.isCancelled, self.queue.revision == token else { return }
      self.loadTask = nil
      guard let document, self.queue.prepare(documentKey: document.key,
        paragraphCount: document.paragraphs.count, token: token), self.media.activate(self) else {
        self.fail(token: token)
        return
      }
      self.play(document, item: item, token: token)
    }
  }

  func pause(relinquish: Bool = false) {
    queue.pause()
    cancelWork()
    persist()
    if relinquish { media.release(self) }
    else { media.suspend(self) }
  }

  func stop() {
    queue.stop()
    cancelWork()
    persist()
    media.release(self)
    controlsVisible = false
  }

  func next() {
    let advance = queue.next()
    cancelWork()
    persist()
    if advance { resume() }
    else {
      media.release(self)
      controlsVisible = false
    }
  }

  private func play(_ document: PublicNewsSpeechDocument, item: PublicNewsSpeechBookmark.Item, token: UInt64) {
    let language = item.edition == .chinese ? "zh-CN" : LanguagePolicySettings.resolve(languagePolicy.ttsLanguage)
    let session = UUID().uuidString
    let request = VoiceReplyPlaybackRequest(
      sessionId: session, utteranceId: "public-news:\(session)", text: "",
      language: language, providerId: settings.ttsProvider.rawValue, runtimeChannel: settings.ttsProvider.runtimeChannel,
      voiceName: settings.ttsProvider == .microsoftEdge
        ? LanguagePolicySettings.microsoftVoice(languageTag: language, configuredVoice: settings.microsoftVoice)
        : ""
    )
    speechStarted = true
    speech.beginProgressive(request, onPlaybackStarted: { [weak self] _ in
      guard let self, self.queue.revision == token else { return }
      self.media.setPlaying(true, owner: self)
    }, onDone: { [weak self] _, success, _ in
      guard let self, self.queue.revision == token else { return }
      self.speechStarted = false
      if success { self.next() }
      else { self.fail(token: token) }
    })
    speech.appendDocumentParagraphs(document.paragraphs[queue.bookmark.paragraph...]) { [weak self] index in
      guard let self, self.queue.revision == token else { return }
      if index != self.queue.bookmark.paragraph {
        guard self.queue.finishedParagraph(index - 1, count: document.paragraphs.count, token: token) else { return }
      }
      if self.queue.began(paragraph: index, token: token) { self.persist() }
    }
  }

  private func fail(token: UInt64) {
    queue.fail(token: token)
    cancelWork()
    persist()
    media.release(self)
  }

  private func cancelWork() {
    loadTask?.cancel()
    loadTask = nil
    if speechStarted {
      speechStarted = false
      _ = speech.stop()
    }
  }

  private func persist() { bookmarks.save(queue.bookmark) }
}
