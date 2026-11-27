import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthAnswerBasisRow: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let conversation: String
  let turn: UUID
  let visible: Bool
  @State private var display: GalaxySSIHealthAnswerBasis.Display?
  @State private var expanded = false
  @State private var mounted = false

  private var canRead: Bool {
    mounted && visible && scene == .active && UIApplication.shared.isProtectedDataAvailable && store.canReadAgentTranscript &&
      records.owner == store.profile.identityFingerprint && store.activeAgentConversationId == conversation &&
      store.agentSession(id: conversation).map { GalaxySSIHealthCareAgentScope.concernID($0) != nil } == true
  }

  var body: some View {
    Group {
      if canRead, let display {
        VStack(alignment: .leading, spacing: 6) {
          Button {
            // Expansion always rereads consent and exact local record/file identity.
            refresh(open: !expanded)
          } label: {
            HStack(spacing: 8) {
              Text(String(format: t("count", "Answer basis · %d sources"), display.sources.count))
                .multilineTextAlignment(.leading)
              Image(systemName: expanded ? "chevron.up" : "chevron.down")
            }
            .frame(minHeight: 44, alignment: .leading)
            .foregroundColor(.galaxySSIAccent)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("ios.health.answer-basis.open")
          .accessibilityValue(expanded ? t("expanded", "Expanded") : t("collapsed", "Collapsed"))
          if expanded {
            Text(t("scope", "Only this turn's approved data and locally verified retrievals. Not model-generated citations."))
              .font(.caption).foregroundColor(.galaxySSITextSecondary)
            ForEach(Array(display.sources.enumerated()), id: \.offset) { _, source in
              VStack(alignment: .leading, spacing: 3) {
                Text(kind(source.kind)).font(.footnote.weight(.medium))
                if let metric = source.metric { Text(metric.title(language: language)) }
                if !source.title.isEmpty { Text(verbatim: source.title) }
                if let at = source.at {
                  HStack { Text(at, style: .date); Text(at, style: .time) }
                    .font(.caption).foregroundColor(.galaxySSITextSecondary)
                }
              }
              .font(.footnote).padding(.vertical, 4)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .onAppear { mounted = true; refresh(open: false) }
    .onDisappear { mounted = false; clear() }
    .onChange(of: visible) { if $0 { refresh(open: false) } else { clear() } }
    .onChange(of: scene) { if $0 == .active { refresh(open: false) } else { clear() } }
    .onChange(of: conversation) { _ in clear() }
    .onChange(of: turn) { _ in clear() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: store.activeAgentConversationId) { _ in clear() }
    .onChange(of: store.canReadAgentTranscript) { if $0 { refresh(open: false) } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { note in
      if note.object as? String == records.owner { refresh(open: false) }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) { note in
      if note.object as? String == records.owner { refresh(open: false) }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { note in
      if note.object as? String == records.owner { refresh(open: false) }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh(open: false) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear() }
    .task(id: display?.until) {
      guard let until = display?.until else { return }
      let seconds = max(0, min(GalaxySSIHealthCareDiscussion.approvalLifetime, until.timeIntervalSinceNow))
      do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
      guard !Task.isCancelled, display?.until == until else { return }
      clear()
    }
  }

  private func clear() { display = nil; expanded = false }
  private func refresh(open: Bool) {
    clear()
    guard canRead, let value = try? records.localCareAnswerBasis(conversation: conversation, turn: turn, expanded: open),
          canRead, Date() < value.until else { return }
    display = value
    expanded = open
  }
  private func kind(_ kind: GalaxySSIHealthAnswerBasis.Kind) -> String {
    switch kind {
    case .measurement: return t("measurement", "Measurement record")
    case .context: return t("context", "Confirmed measurement context")
    case .profile: return t("profile", "Selected self-reported profile")
    case .guideline: return t("guideline", "Guideline reference")
    case .target: return t("target", "Confirmed individual target")
    case .retrieved: return t("retrieved", "Locally retrieved public source")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.answer_basis." + key, fallback: fallback, language: language)
  }
}
