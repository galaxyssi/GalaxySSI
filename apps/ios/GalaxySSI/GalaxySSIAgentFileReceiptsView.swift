import SwiftUI

private struct AgentFileReceiptSourceKey: EnvironmentKey { static let defaultValue: ChatMessage? = nil }
extension EnvironmentValues {
  var agentFileReceiptSource: ChatMessage? {
    get { self[AgentFileReceiptSourceKey.self] }
    set { self[AgentFileReceiptSourceKey.self] = newValue }
  }
}

struct GalaxySSIAgentFileReceiptsView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scenePhase
  let message: ChatMessage
  let t: (String, String) -> String
  var onlyItemID: String? = nil
  @State private var receipts: [String: AgentFileReceipt] = [:]
  @State private var work: [String: Task<Void, Never>] = [:]
  @State private var errors: Set<String> = []
  @State private var visible = false

  var body: some View {
    let originals = AgentFileReceipt.originals(message)
    let blocks = originals.filter { onlyItemID == nil || $0.id == onlyItemID }
    if originals.count >= 2, store.canReadAgentTranscript, message.conversationId == store.activeAgentConversationId {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(blocks) { block in
          let receipt = receipts[AgentTurnReceiptEvidence.hash(block.id)]
          VStack(alignment: .leading, spacing: 4) {
            if onlyItemID == nil {
              Label(block.title, systemImage: block.type == .image ? "photo" : "doc")
                .font(.caption).lineLimit(2)
            }
            Text(wireLabel(receipt?.wire)).font(.caption2).foregroundColor(.secondary)
            if let reading = receipt?.reading {
              Text(reading == .recognized ? t("galaxyssi.agent.file.recognized", "Model reports: recognized") :
                t("galaxyssi.agent.file.unreadable", "Model reports: unreadable"))
                .font(.caption2).foregroundColor(.secondary)
            } else if receipt?.readTurn != nil {
              Text(t("galaxyssi.agent.file.requested", "Interpretation requested; no model report yet"))
                .font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
              if work[block.id] != nil { ProgressView().frame(width: 16, height: 16) }
              if receipt?.wire == .failed {
                Button { run(block, resume: true) } label: {
                  Label(t("galaxyssi.agent.file.resume", "Resume this file"), systemImage: "arrow.clockwise")
                }
                .disabled(work[block.id] != nil)
              } else if receipt?.wire != .uploading, receipt?.wire != .retrying, receipt?.reading != .recognized {
                Button { run(block, resume: false) } label: {
                  Label(t("galaxyssi.agent.file.read_one", "Read this file only"), systemImage: "doc.text.magnifyingglass")
                }
                .disabled(work[block.id] != nil)
              }
            }
            .buttonStyle(.borderless).font(.caption).frame(minHeight: 32, alignment: .leading)
            if errors.contains(block.id) {
              Text(t("galaxyssi.agent.file.unavailable", "This file or its current route is unavailable. No original question was resent."))
                .font(.caption2).foregroundColor(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("ios.agent.file-receipt." + block.id)
        }
      }
      .padding(.vertical, 6)
      .onAppear { visible = true; reload() }
      .onDisappear { visible = false; clear() }
      .onChange(of: store.activeAgentConversationId) { _ in clear() }
      .onChange(of: scenePhase) { phase in if phase == .active { reload() } else { clear() } }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentFileReceiptChanged)) { _ in reload() }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear() }
    }
  }
  private func wireLabel(_ state: AgentFileReceipt.Wire?) -> String {
    switch state {
    case .uploading: return t("galaxyssi.agent.file.uploading", "Transferring")
    case .retrying: return t("galaxyssi.agent.file.retrying", "Resuming transfer")
    case .failed: return t("galaxyssi.agent.file.failed", "Transfer paused after failure")
    case .stored: return t("galaxyssi.agent.file.stored", "Peer confirmed file storage")
    case .closed: return t("galaxyssi.agent.file.closed", "Transfer closed without verified delivery")
    case nil: return t("galaxyssi.agent.file.unknown", "No file delivery receipt")
    }
  }
  private func reload() {
    guard visible, store.canReadAgentTranscript, message.conversationId == store.activeAgentConversationId,
      let key = store.turnReceiptKey(conversation: message.conversationId, turn: message.turnId) else { receipts = [:]; return }
    receipts = store.turnReceiptStore.read(key)?.files ?? [:]
  }
  private func clear() {
    work.values.forEach { $0.cancel() }; work.removeAll(); errors.removeAll(); receipts.removeAll()
  }
  private func run(_ block: AgentRichBlock, resume: Bool) {
    guard visible, scenePhase == .active, work[block.id] == nil else { return }
    errors.remove(block.id)
    let owner = store.profile.identityFingerprint
    work[block.id] = Task { @MainActor in
      let success = resume
        ? await coordinator.resumeAgentFile(messageID: message.id, itemID: block.id)
        : await coordinator.readAgentFile(messageID: message.id, itemID: block.id)
      guard !Task.isCancelled, visible, owner == store.profile.identityFingerprint,
        message.conversationId == store.activeAgentConversationId else { return }
      work.removeValue(forKey: block.id)
      if !success { errors.insert(block.id) }
      reload()
    }
  }
}
