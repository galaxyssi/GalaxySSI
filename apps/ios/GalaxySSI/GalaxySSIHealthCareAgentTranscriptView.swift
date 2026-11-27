import Combine
import SwiftUI
import UIKit

struct GalaxySSIHealthCareTranscriptRevision: Equatable {
  var conversation = ""
  var revision = 0
  var hasRows = false
}

struct GalaxySSIHealthCareTranscriptRevisionKey: PreferenceKey {
  static var defaultValue = GalaxySSIHealthCareTranscriptRevision()
  static func reduce(value: inout GalaxySSIHealthCareTranscriptRevision, nextValue: () -> GalaxySSIHealthCareTranscriptRevision) {
    let next = nextValue()
    if !next.conversation.isEmpty { value = next }
  }
}

@MainActor
struct GalaxySSIHealthCareAgentTranscriptView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let conversation: String
  let visible: Bool
  let legacyMessages: [ChatMessage]
  let legacyRuntimeTurns: Set<String>
  @State private var legacyMarkers: [GalaxySSIHealthCareLegacyReplyPresentation.Marker] = []
  @State private var rows: [GalaxySSIHealthCareAgentTranscriptProjection.Row] = []
  @State private var target: GalaxySSIHealthCare.AgentDiscussionTarget?
  @State private var displayedOwner = ""
  @State private var displayedConversation = ""
  @State private var limit = 24
  @State private var reviewPresented = false
  @State private var revision = 0

  private var canRead: Bool {
    visible && scene == .active && UIApplication.shared.isProtectedDataAvailable && store.canReadAgentTranscript &&
      records.owner == store.profile.identityFingerprint && store.activeAgentConversationId == conversation &&
      store.agentSession(id: conversation).map { GalaxySSIHealthCareAgentScope.concernID($0) != nil } == true
  }

  var body: some View {
    Group {
      if canRead, displayedOwner == records.owner, displayedConversation == conversation {
        ForEach(legacyMarkers) { marker in
          VStack(alignment: .leading, spacing: 8) {
            Text(String(format: t("processed_seconds", "Worked for %d s"), marker.seconds))
              .font(.footnote).foregroundColor(.galaxySSITextSecondary).monospacedDigit()
            Divider()
            Text(t("interrupted_control", "This reply contains unexecuted Agent instructions. The question and reply were retained privately. Nothing was executed or resent."))
              .foregroundColor(.galaxySSITextSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
          .accessibilityIdentifier("health-agent-legacy-interrupted-" + marker.id.uuidString)
        }
        if rows.count > limit {
          Button(t("more", "Show earlier messages")) { limit += 24 }
        }
        ForEach(rows.suffix(limit)) { row in
          VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: row.question)
              .padding(.horizontal, 14).padding(.vertical, 10)
              .foregroundColor(.galaxySSITextPrimary)
              .background(Color.galaxySSISentBubble)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .frame(maxWidth: .infinity, alignment: .trailing)
            if let clock = row.clock {
              TimelineView(.periodic(from: Date(), by: 1)) { context in
                HStack(spacing: 8) {
                  if clock.running(at: context.date) { ProgressView() }
                  Text(String(format: clock.running(at: context.date)
                    ? t("processing_seconds", "Working for %d s") : t("processed_seconds", "Worked for %d s"),
                    clock.seconds(at: context.date)))
                    .font(.footnote).foregroundColor(.galaxySSITextSecondary).monospacedDigit()
                }
                if clock.stoppedAt == nil, !clock.running(at: context.date) {
                  Text(t("request_interrupted", "This request was interrupted. It has not been resent."))
                    .font(.footnote).foregroundColor(.galaxySSITextSecondary)
                }
              }
              Divider()
            }
            reply(row.reply)
            if case .answer = row.reply {
              GalaxySSIHealthAnswerBasisRow(records: records, conversation: conversation, turn: row.id, visible: canRead)
            }
          }
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("health-agent-turn-" + row.id.uuidString)
        }
        if !rows.isEmpty || !legacyMarkers.isEmpty {
          Button { refresh(); reviewPresented = target != nil } label: {
            Label(t("title", "Private Health Discussion"), systemImage: "bubble.left.and.bubble.right")
              .frame(minHeight: 44)
          }
        }
      }
    }
    .preference(key: GalaxySSIHealthCareTranscriptRevisionKey.self,
      value: .init(conversation: canRead ? conversation : "", revision: revision,
        hasRows: canRead && (!rows.isEmpty || !legacyMarkers.isEmpty)))
    .onAppear(perform: refresh)
    .onChange(of: visible) { if $0 { refresh() } else { clear() } }
    .onChange(of: scene) { if $0 == .active { refresh() } else { clear() } }
    .onChange(of: store.activeAgentConversationId) { _ in clear() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: store.canReadAgentTranscript) { if $0 { refresh() } else { clear() } }
    .onChange(of: legacyMessages) { _ in refresh() }
    .onChange(of: legacyRuntimeTurns) { _ in refresh() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
      if $0.object as? String == records.owner { refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIWorkspaceDidPersist)
      .debounce(for: .milliseconds(75), scheduler: RunLoop.main)) { _ in refresh() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in refresh() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear() }
    .sheet(isPresented: $reviewPresented) {
      if canRead, let target, let archive = try? records.load(), target.matches(archive) {
        NavigationView {
          GalaxySSIHealthCareDiscussionView(records: records, concernID: target.id, metric: target.metric)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button(t("close", "Close")) { reviewPresented = false }
              }
            }
        }.navigationViewStyle(.stack)
      }
    }
  }

  @ViewBuilder
  private func reply(_ value: GalaxySSIHealthCareAgentTranscriptProjection.Reply) -> some View {
    switch value {
    case .answer(let text): Text(verbatim: text).textSelection(.enabled).foregroundColor(.galaxySSITextPrimary)
    case .plan: Text(t("plan_retained", "Draft available in Health plans"))
    case .questions: Text(q("retained", "Questions are available in Personal Health."))
    case .answerDraft: Text(q("draft_staged", "Clarification answer draft created"))
    case .interruptedControl:
      Text(t("interrupted_control", "This reply contains unexecuted Agent instructions. The question and reply were retained privately. Nothing was executed or resent."))
        .foregroundColor(.galaxySSITextSecondary)
    case .interruptedRequest:
      Text(t("request_interrupted", "This request was interrupted. It has not been resent."))
        .foregroundColor(.galaxySSITextSecondary)
    case .waiting: EmptyView()
    case .noSavedReply: Text(t("unanswered", "No saved reply")).foregroundColor(.galaxySSITextSecondary)
    }
  }

  private func refresh() {
    guard canRead, let session = store.agentSession(id: conversation), let archive = try? records.load(),
          let concern = GalaxySSIHealthCareAgentScope.concern(session, in: archive),
          let thread = archive.localCareDiscussions?[concern.id.uuidString] else { clear(); return }
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: records)
    let nextRows = GalaxySSIHealthCareAgentTranscriptProjection.rows(thread, owner: records.owner, conversation: conversation,
      workspaces: runtime.persistedWorkspaces(), isExecuting: { runtime.isExecuting($0) })
    let nextLegacy = legacyRows(session: session, domainTurns: Set(thread.turns.map(\.id)))
    if rows != nextRows || legacyMarkers != nextLegacy {
      rows = nextRows; legacyMarkers = nextLegacy; revision &+= 1
    }
    displayedOwner = records.owner
    displayedConversation = conversation
    let next = GalaxySSIHealthCare.AgentDiscussionTarget(concern,
      permission: GalaxySSIHealthCare.AgentDiscussionTarget.permission(in: archive))
    if target?.id != next.id { reviewPresented = false }
    target = next
  }

  private func clear() {
    rows = []; legacyMarkers = []; target = nil; displayedOwner = ""; displayedConversation = ""; limit = 24; reviewPresented = false
    revision &+= 1
  }
  private func legacyRows(session: AgentConversation, domainTurns: Set<UUID>) -> [GalaxySSIHealthCareLegacyReplyPresentation.Marker] {
    guard legacyMessages.contains(where: GalaxySSIHealthCareLegacyReplyPresentation.isControl),
          let verified = try? store.chatHistoryDatabase.verifiedHealthLegacyWindow(conversationId: session.id) else { return [] }
    var seen = Set<UUID>()
    return legacyMessages.sorted { $0.createdAt < $1.createdAt }.compactMap { receipt in
      guard GalaxySSIHealthCareLegacyReplyPresentation.isControl(receipt),
            let sourceID = UUID(uuidString: receipt.turnId),
            !seen.contains(sourceID),
            verified.contains(receipt),
            let original = verified.first(where: { $0.id == sourceID && $0.isMine && !$0.isSystem }),
            store.agentTask(id: receipt.turnId) == nil,
            store.agentWorkspaceStore.find(receipt.turnId) == nil else { return nil }
      let hasAnswer = verified.contains {
        $0.conversationId == session.id && $0.turnId == receipt.turnId && !$0.isMine && !$0.isSystem &&
          [.delivered, .read].contains($0.deliveryStatus) && !GalaxySSIHealthCareLegacyReplyPresentation.isControl($0)
      }
      guard let marker = GalaxySSIHealthCareLegacyReplyPresentation.marker(receipt: receipt, original: original,
        conversation: session, hasRecovery: legacyRuntimeTurns.contains(receipt.turnId),
        domainTurns: domainTurns, hasAnswer: hasAnswer) else { return nil }
      seen.insert(marker.turn)
      return marker
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.discussion." + key, fallback: fallback, language: language)
  }
  private func q(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.questions." + key, fallback: fallback, language: language)
  }
}
