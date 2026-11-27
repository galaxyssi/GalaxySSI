import SwiftUI
import UIKit

@MainActor
private final class GalaxySSILocalMessageSearchModel: ObservableObject {
  typealias Search = GalaxySSILocalMessageSearch
  @Published private(set) var hits: [Search.Hit] = []
  @Published private(set) var busy = false
  @Published private(set) var more = false
  @Published private(set) var failed = false
  private var worker: Task<Void, Never>?
  private var scanner: GalaxySSILocalMessageSearchScanner?
  private var token = UUID()
  private var scannerOwner = ""
  func stop() { token = UUID(); worker?.cancel(); worker = nil; scanner = nil; scannerOwner = ""; hits = []; busy = false; more = false; failed = false }
  func start(owner: String, query: String, archived: Bool, peers: [Search.Source], store: GalaxySSIStore) {
    stop()
    guard !owner.isBlank, let clean = Search.query(query), store.canReadAgentTranscript else { return }
    scannerOwner = owner
    scanner = .init(owner: owner, query: clean, archived: archived, peers: peers,
      conversations: store.agentConversationDatabase, messages: store.chatHistoryDatabase)
    read(store: store, owner: owner, delay: true)
  }
  func read(store: GalaxySSIStore, owner: String, delay: Bool = false) {
    guard !busy, scannerOwner == owner, let scanner else { return }
    let epoch = token
    busy = true; failed = false
    worker = Task {
      do {
        if delay { try await Task.sleep(nanoseconds: 220_000_000) }
        let goal = hits.count + 24
        while hits.count < goal {
          let batch = try await scanner.next(limit: hits.isEmpty ? 1 : min(6, goal - hits.count))
          guard !Task.isCancelled, token == epoch, store.profile.identityFingerprint == owner,
            store.canReadAgentTranscript, UIApplication.shared.isProtectedDataAvailable else { return }
          hits += batch.hits.filter { $0.owner == owner && Search.allowed($0.source, store: store) }
          more = batch.more
          if !batch.more { break }
        }
        if token == epoch { busy = false }
      } catch {
        guard !Task.isCancelled, token == epoch else { return }
        busy = false; more = false; failed = true
      }
    }
  }
  func prune(store: GalaxySSIStore) {
    hits.removeAll { $0.owner != store.profile.identityFingerprint || !Search.allowed($0.source, store: store) }
  }
}

@MainActor
struct GalaxySSILocalMessageSearchView: View {
  typealias Search = GalaxySSILocalMessageSearch
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @StateObject private var model = GalaxySSILocalMessageSearchModel()
  @State private var selected: Search.Hit?
  let query: String
  let archived: Bool
  let enabled: Bool
  private struct Request: Equatable {
    let owner: String
    let query: String
    let archived: Bool
    let peers: [Search.Source]
    let active: Bool
  }
  private var request: Request {
    .init(owner: store.profile.identityFingerprint, query: query, archived: archived,
      peers: store.conversationHistoryContacts.compactMap { Search.peer($0, archived: archived) },
      active: enabled && scene == .active && store.canReadAgentTranscript && UIApplication.shared.isProtectedDataAvailable)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(t("heading", "Messages and attachments")).font(.subheadline.weight(.semibold)).padding(12)
      if request.active {
        ForEach(model.hits) { hit in
          Button {
            guard hit.owner == store.profile.identityFingerprint, Search.allowed(hit.source, store: store) else { return }
            selected = hit
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(verbatim: hit.source.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(hit.at, style: .date).font(.caption).foregroundColor(.secondary)
              }
              HStack(alignment: .top) {
                if hit.filename { Image(systemName: "paperclip").accessibilityLabel(t("attachment", "Attachment")) }
                Text(verbatim: hit.snippet).font(.subheadline).lineLimit(3)
              }
              .foregroundColor(.galaxySSITextPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain).id(hit.id)
          .accessibilityIdentifier("ios.local-message-search.hit")
          Divider()
        }
        if model.busy { ProgressView().frame(maxWidth: .infinity).padding(12) }
        else if Search.query(query) == nil { Text(t("query_limit", "Enter up to 256 characters.")).padding(12) }
        else if model.hits.isEmpty && !model.failed { Text(t("empty", "No matching messages")).foregroundColor(.secondary).padding(12) }
        if model.failed { Text(t("failed", "Search could not finish. Results may be incomplete.")).foregroundColor(.secondary).padding(12) }
        if model.failed {
          Button(t("retry", "Retry search")) {
            model.start(owner: request.owner, query: query, archived: archived, peers: request.peers, store: store)
          }.frame(minHeight: 44).padding(.horizontal, 12)
        }
        if model.more && !model.busy {
          Button(t("more", "More matching messages")) { model.read(store: store, owner: request.owner) }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
      }
    }
    .privacySensitive()
    .task(id: request) {
      selected = nil
      let value = request
      if value.active { model.start(owner: value.owner, query: value.query, archived: value.archived, peers: value.peers, store: store) }
      else { model.stop() }
    }
    .onDisappear { model.stop(); selected = nil }
    .onChange(of: scene) { if $0 != .active { model.stop(); selected = nil } }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in model.stop(); selected = nil }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in model.stop(); selected = nil }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIWorkspaceDidPersist)) { _ in
      model.prune(store: store)
      if let selected, !Search.allowed(selected.source, store: store) { self.selected = nil }
    }
    .sheet(item: $selected) { hit in
      GalaxySSILocalMessageReader(hit: hit, query: Search.query(query) ?? "")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.chat_search." + key, fallback: fallback, language: language)
  }
}
