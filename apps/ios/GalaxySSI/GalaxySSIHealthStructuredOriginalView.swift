import SwiftUI

@MainActor
struct GalaxySSIHealthStructuredOriginalView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let store: GalaxySSIHealthOriginalStore
  let original: GalaxySSIHealthOriginalStore.Original
  @State private var request = UUID()
  @State private var enabled = true
  @State private var loading = false
  @State private var failed = false
  @State private var sheetID = ""
  @State private var preview: GalaxySSIHealthStructuredOriginal.Preview?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if scene == .active {
        if let preview {
          if !preview.sheets.isEmpty {
            Picker(t("sheet", "Worksheet"), selection: Binding(get: { sheetID }, set: selectSheet)) {
              ForEach(preview.sheets) { Text($0.name).tag($0.id) }
            }
          }
          if preview.sample.limited {
            Text(t("grid_limited", "Preview limited to 20 rows, 12 columns and 512 characters per cell."))
              .font(.footnote).foregroundColor(.secondary)
          }
          if preview.sample.rows.isEmpty { Text(t("empty_source", "No source rows.")).foregroundColor(.secondary) }
          else { GalaxySSIHealthTablePreviewGrid(sample: preview.sample).id(request) }
        }
        if loading {
          ProgressView(t("loading", "Loading preview"))
          Button(t("cancel_preview", "Cancel preview"), action: invalidate)
        }
        if failed { Text(t("unavailable", "The original or its preview is unavailable.")).foregroundColor(.secondary) }
        if failed || !enabled { Button(t("reload", "Reload original"), action: reload) }
      }
    }
    .task(id: request) { await load() }
    .onAppear { if !enabled { reload() } }
    .onDisappear(perform: invalidate)
    .onChange(of: scene) { if $0 == .active { reload() } else { invalidate() } }
    .onChange(of: store.owner) { _ in invalidate() }
    .onChange(of: store.restoreRecordsFile) { _ in invalidate() }
    .onChange(of: original) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in invalidate() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) {
      if $0.object as? String == store.owner { invalidate() }
    }
  }

  private func invalidate() {
    request = UUID(); enabled = false; loading = false; failed = false; preview = nil; sheetID = ""
  }
  private func reload() { invalidate(); enabled = true }
  private func selectSheet(_ id: String) {
    guard preview?.sheets.contains(where: { $0.id == id }) == true, id != sheetID else { return }
    invalidate(); sheetID = id; enabled = true
  }
  private func load() async {
    guard enabled, scene == .active, !Task.isCancelled, original.kind == .structured else { return }
    let token = request, owner = store.owner, dataset = store.restoreRecordsFile, selected = sheetID
    loading = true
    do {
      try store.validateOriginalSelection([original])
      let data = try store.read(original)
      let ext = original.fileExtension, headers = [t("json_key", "Key"), t("json_value", "Value")]
      let worker = Task.detached(priority: .userInitiated) {
        try GalaxySSIHealthStructuredOriginal.read(data, fileExtension: ext, sheetID: selected, jsonHeaders: headers)
      }
      let loaded = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
      guard request == token, !Task.isCancelled, scene == .active,
            store.owner == owner, store.restoreRecordsFile == dataset else { return }
      try store.validateOriginalSelection([original])
      sheetID = loaded.sheetID
      preview = loaded
    } catch {
      if request == token, !Task.isCancelled, scene == .active { failed = true }
    }
    if request == token { loading = false }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.table_source." + key, fallback: fallback, language: language)
  }
}
