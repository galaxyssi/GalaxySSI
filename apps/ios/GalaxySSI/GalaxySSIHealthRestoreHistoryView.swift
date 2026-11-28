import SwiftUI

@MainActor
struct GalaxySSIHealthRestoreHistoryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  @State private var entries: [GalaxySSIHealthRestoreReceipt] = []
  @State private var limit = 10
  @State private var failed = false
  @State private var visible = false

  var body: some View {
    Form {
      if scene == .active {
        if failed {
          Section {
            Text(t("failed", "Could not read local restore history."))
            Button(t("retry", "Retry"), action: reload)
          }
        } else {
          if entries.isEmpty { Text(t("empty", "No recorded restores. Earlier restores have no detailed receipt.")) }
          ForEach(entries.prefix(limit)) { receipt in
            Section { GalaxySSIHealthRestoreReceiptRows(receipt: receipt) }
          }
          if entries.count > limit {
            Button(t("more", "Show older restores")) { limit = min(limit + 10, GalaxySSIHealthRestoreReceipt.maximumHistory) }
          }
        }
      }
    }
    .navigationTitle(t("title", "Restore history"))
    .galaxySSIHealthTheme()
    .onAppear { visible = true; reload() }
    .onDisappear { visible = false; clear() }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onChange(of: records.owner) { _ in clear(); reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
  }

  private func reload() {
    guard visible, scene == .active else { clear(); return }
    do {
      let archive = try records.load()
      let history = archive.restoreHistory ?? []
      guard GalaxySSIHealthRestoreReceipt.validHistory(history, committed: archive.restoreReceipts ?? []) else {
        throw GalaxySSIHealthRestoreReceipt.Failure.invalid
      }
      entries = history.sorted { ($0.at, $0.id.uuidString) > ($1.at, $1.id.uuidString) }
      failed = false
    } catch { entries = []; failed = true }
  }

  private func clear() { entries = []; limit = 10; failed = false }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.restore_receipt." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthRestoreReceiptRows: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let receipt: GalaxySSIHealthRestoreReceipt

  var body: some View {
    Group {
      Text(receipt.at, format: .dateTime)
      Text(receipt.counts.unresolved ? t("partial", "Committed with unresolved items") : t("committed", "Restore committed"))
        .foregroundColor(receipt.counts.unresolved ? .orange : .secondary)
      if let first = receipt.first, let last = receipt.last {
        Text(first.formatted(date: .abbreviated, time: .omitted) + " - " + last.formatted(date: .abbreviated, time: .omitted))
      }
      Group {
      row("added", "New measurements", receipt.counts.added)
      row("duplicates", "Duplicate measurements", receipt.counts.duplicates)
      row("conflicts", "Unreplaced conflicts", receipt.counts.conflicts)
      row("replaced", "Replaced measurements", receipt.counts.replaced)
      }
      Group {
      row("originals_added", "Original files added", receipt.counts.originalsAdded)
      row("originals_reused", "Original files reused", receipt.counts.originalsReused)
      row("originals_repaired", "Original files staged for repair", receipt.counts.originalsRepaired)
      row("originals_unavailable", "Unavailable original files", receipt.counts.originalsUnavailable)
      row("tables", "Tables added", receipt.counts.tablesAdded)
      }
      Group {
      row("sources_added", "Source links added", receipt.counts.sourcesAdded)
      row("sources_reused", "Source links reused", receipt.counts.sourcesReused)
      row("sources_skipped", "Source links skipped", receipt.counts.sourcesSkipped)
      row("missing", "Missing source references", receipt.counts.missingReferences)
      }
      Text(t("file_note", "These are committed restore counts, not a verification of current original-file availability."))
        .font(.footnote).foregroundColor(.secondary)
    }
  }

  private func row(_ key: String, _ fallback: String, _ count: Int) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(t(key, fallback))
      Spacer(minLength: 12)
      Text(count.formatted()).monospacedDigit().fixedSize()
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.restore_receipt." + key, fallback: fallback, language: language)
  }
}
