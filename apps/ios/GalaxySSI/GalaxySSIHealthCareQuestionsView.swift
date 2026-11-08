import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareQuestionsView: View {
  typealias Questions = GalaxySSIHealthCareQuestions
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concern: UUID
  let metric: GalaxySSIHealthMetric
  @State private var page: Questions.Page?
  @State private var cursors: [UUID] = []
  @State private var reviewing: Questions.Row?
  @State private var answer = ""
  @State private var failed = false

  var body: some View {
    Section(t("title", "Clarification questions")) {
      if canRead, let page {
        if page.rows.isEmpty { Text(t("empty", "No questions recorded")).foregroundColor(.secondary) }
        ForEach(page.rows) { row in
          Button {
            answer = page.state(row) == .stale ? "" : (row.answer ?? "")
            reviewing = row
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(row.proposal.question)
              Text(label(page.state(row))).font(.caption).foregroundColor(.secondary)
            }
          }
        }
        if !cursors.isEmpty || page.next != nil {
          HStack {
            Button(t("previous", "Previous")) {
              if !cursors.isEmpty { cursors.removeLast(); reload() }
            }.disabled(cursors.isEmpty)
            Spacer()
            Button(t("next", "Next")) {
              if let next = page.next { cursors.append(next); reload() }
            }.disabled(page.next == nil)
          }.buttonStyle(.borderless)
        }
      }
      if failed { Text(t("unavailable", "The question or its source changed. Review it again.")) }
    }
    .onAppear(perform: reload)
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onChange(of: store.profile.identityFingerprint) { _ in clear(); reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reviewing = nil; answer = ""; reload() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
      if $0.object as? String == records.owner { clear(); reload() }
    }
    .sheet(item: $reviewing) { row in
      NavigationView {
        List {
          if canRead, let page {
            Section {
              Text(row.proposal.question).font(.headline)
              Text(row.proposal.purpose)
              Text(label(page.state(row))).foregroundColor(.secondary)
              if let fact = page.known[row.proposal.key] {
                Text(t("saved_fact", "Saved fact") + ": " + AgentMcpJSONCodec.stringify(fact))
              }
            }
            if [.deferred, .declined, .stale].contains(page.state(row)) || [.deferred, .declined].contains(row.state) {
              Button(t("reopen", "Reopen for review")) { save(row, state: .open) }
            } else {
              TextField(t("answer", "Your reviewed reply"), text: $answer)
              Button(t("save", "Confirm reply")) { save(row, state: .answered, text: answer) }
                .disabled(answer.isBlank || answer.utf8.count > 2_000)
              Button(t("defer", "Defer")) { save(row, state: .deferred) }
              Button(t("decline", "Decline to answer")) { save(row, state: .declined) }
            }
          }
        }
        .navigationTitle(t("title", "Clarification questions"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { reviewing = nil; answer = "" } }
        }
      }.navigationViewStyle(.stack)
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func reload() {
    guard canRead else { clear(); return }
    do {
      page = try records.localCareQuestionPage(id: concern, metric: metric, after: cursors.last)
    } catch {
      cursors = []
      page = try? records.localCareQuestionPage(id: concern, metric: metric)
    }
  }

  private func save(_ row: Questions.Row, state: Questions.State, text: String? = nil) {
    guard canRead, reviewing?.id == row.id else { return }
    do {
      try records.reviewLocalCareQuestion(id: concern, metric: metric, row: row, state: state, answer: text)
      failed = false
    } catch { failed = true }
    reviewing = nil; answer = ""
    reload()
  }

  private func clear() {
    page = nil; reviewing = nil; answer = ""; cursors = []; failed = false
  }

  private func label(_ state: Questions.State) -> String {
    switch state {
    case .open: return t("open", "Awaiting review")
    case .answered: return t("answered", "Answered")
    case .deferred: return t("deferred", "Deferred")
    case .declined: return t("declined", "Declined")
    case .conflict: return t("conflict", "Conflicts with a saved fact")
    case .stale: return t("stale", "Source changed")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.questions." + key, fallback: fallback, language: language)
  }
}
