import SwiftUI

struct AgentTurnReceiptTarget: Identifiable {
  let key: AgentTurnReceiptStore.Key
  let completedAt: Int64?
  var id: String { key.row }
}

struct GalaxySSITurnReceiptView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let target: AgentTurnReceiptTarget
  @State private var receipt: AgentTurnReceipt?
  private var missing: String { t("missing", "Unknown / not reported") }
  var body: some View {
    NavigationView {
      Form {
        Section(header: Text(t("timing", "Timing"))) {
          row("sent", "Phone sent", clock(receipt?.sent))
          row("desktop", "Desktop MQTT received", clock(receipt?.desktopReceived))
          row("body", "First visible reply on this phone", visibleTime)
          row("result", "Terminal reply received on this phone", clock(receipt?.resultAt))
          row("done", "Task completed", clock(target.completedAt))
        }
        Section(header: Text(t("route", "Model and operation provenance"))) {
          row("choice", "Selection at send", info([receipt?.mode.map { $0 == "automatic" ? t("auto", "Auto") : t("manual", "Manual") }, receipt?.requested, receipt?.effort]))
          if receipt?.wire != nil || receipt?.desktopReceived != nil || receipt?.provider != nil {
            row("wire", "Requested from Desktop", info([receipt?.wire, receipt?.wireEffort]))
            row("submitted", "Desktop reported submission", info([receipt?.provider, receipt?.submitted, receipt?.submittedEffort]))
            row("desktop_actual", "Actual Desktop provider model", missing)
          }
          if receipt?.cloudRequested != nil || (receipt?.wire == nil && receipt?.localProfile == nil) {
            row("cloud", "Direct cloud requested model", info([receipt?.cloudRequested]))
            row("actual", "Cloud response reported model", info([receipt?.cloudActual]))
            row("actual_effort", "Cloud response reported effort", info([receipt?.cloudEffort]))
          }
          if receipt?.localProfile != nil { row("local", "Observed local runtime profile", info([receipt?.localProfile])) }
          row("device", "Operation device from tool receipts", info([
            receipt?.phoneExecuted == true ? t("phone", "This phone") : nil,
            receipt?.desktopExecuted == true ? "Desktop" : nil]))
        }
      }
      .navigationTitle(t("title", "Turn receipt")).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) {
        Button { dismiss() } label: { Image(systemName: "xmark") }
          .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))
      } }
    }
    .navigationViewStyle(.stack)
    .onAppear {
      guard store.canReadAgentTranscript, store.profile.identityFingerprint == target.key.owner,
            store.activeAgentConversationId == target.key.conversation else { dismiss(); return }
      receipt = store.turnReceiptStore.read(target.key)
    }
    .onChange(of: store.activeAgentConversationId) { _ in dismiss() }
    .onChange(of: store.profile.identityFingerprint) { _ in receipt = nil; dismiss() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in receipt = nil; dismiss() }
  }
  private var visibleTime: String {
    guard let millis = receipt?.bodyMillis else { return clock(receipt?.body) }
    return String(format: t("since", "%@ (%@ s since send)"), clock(receipt?.body),
      NumberFormatter.localizedString(from: NSNumber(value: Double(millis) / 1_000), number: .decimal))
  }
  private func clock(_ millis: Int64?) -> String {
    guard let millis, millis > 0 else { return missing }
    let formatter = DateFormatter(); formatter.locale = GalaxySSILocalization.interfaceLocale(language: language)
    formatter.timeStyle = .medium; return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }
  private func info(_ values: [String?]) -> String {
    let result = values.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    return result.isEmpty ? missing : result
  }
  private func row(_ key: String, _ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(t(key, title)).font(.caption).foregroundColor(.secondary)
      Text(verbatim: value).font(.body).textSelection(.enabled)
    }.padding(.vertical, 3)
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("turn_receipt_" + key, fallback: fallback, language: language)
  }
}
