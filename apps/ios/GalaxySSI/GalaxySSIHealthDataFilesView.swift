import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthDataFilesView<Metrics: View, Review: View>: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.dynamicTypeSize) private var typeSize
  let records: GalaxySSIHealthRecords
  let metrics: () -> Metrics
  let review: () -> Review
  @State private var recent: [GalaxySSIHealthDataFiles.Recent]?
  @State private var measurements: Int?
  @State private var counts: GalaxySSIHealthDataFiles.Counts?
  @State private var failed = false
  @State private var visible = false
  @State private var request: Task<Void, Never>?
  @State private var menu: ActionGroup?
  @State private var route: Route?
  @State private var navigating = false
  @State private var scroll = ScrollReference()
  @SceneStorage("galaxyssi.health.dataFiles.scrollOffset") private var offset = 0.0
  @State private var restoreOffset = true

  private enum ActionGroup { case imports, exports, tasks, backup }
  private enum Route {
    case measurementsImport, originalsImport, measurementsExport, originalsExport, review, tableHistory
    case measurementsHistory, originalsHistory, backup(GalaxySSIHealthBackupView.Entry)
    case original(GalaxySSIHealthDataFiles.Reference)
  }

  private var store: GalaxySSIHealthOriginalStore {
    .init(owner: records.owner, secrets: records.secrets, restoreRecordsFile: records.isolatedFile)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        summary
        actions
        VStack(alignment: .leading, spacing: 8) {
          heading(t("manage", "Manage data"))
          VStack(spacing: 0) {
            NavigationLink(destination: metrics) {
              manage(t("metrics", "Health measurements"), t("metrics_note", "Daily metrics, lab records and conditions"),
                     icon: "chart.bar.xaxis", accent: .green)
            }.buttonStyle(.plain)
            Divider()
            NavigationLink { GalaxySSIHealthOriginalsView(store: store) } label: {
              manage(t("originals", "Photos and uploads"), t("originals_note", "Photos, PDFs and their record links"),
                     icon: "doc.on.doc", accent: .orange)
            }.buttonStyle(.plain)
            Divider()
            Button { menu = .tasks } label: {
              manage(t("tasks", "Import and export tasks"), t("tasks_note", "Review imports and export history"),
                     icon: "clock.arrow.circlepath", accent: .blue)
            }.buttonStyle(.plain)
            Divider()
            Button { menu = .backup } label: {
              manage(t("backup", "Backup and restore"), t("backup_note", "Move records, originals and links together"),
                     icon: "shield", accent: .purple)
            }.buttonStyle(.plain)
          }
          .background(panel)
        }
        recentSection
      }
      .padding(16)
      .background(ScrollResolver(reference: scroll))
    }
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    .background {
      NavigationLink(destination: destination, isActive: $navigating) { EmptyView() }.hidden()
    }
    .navigationTitle(t("title", "Data and Files"))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(menuTitle, isPresented: Binding(
      get: { menu != nil }, set: { if !$0 { menu = nil } }
    ), titleVisibility: .visible) { menuActions }
    .onAppear { visible = true; reload() }
    .onDisappear { visible = false; clear() }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else {
        clear()
        if case .some(.original(_)) = route {
          navigating = false
          route = nil
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notification in
      if notification.object as? String == records.owner { reload() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { notification in
      if notification.object as? String == records.owner { reload() }
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(t("local", "Local health archive")).font(.subheadline).foregroundColor(.secondary)
      heading(t("heading", "Your records and original files"), size: .title2)
      Text(t("note", "Find records and originals, or move them to another device."))
        .font(.subheadline).foregroundColor(.secondary)
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) { stats }
      } else {
        HStack(alignment: .top, spacing: 8) { stats }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
  }

  @ViewBuilder private var stats: some View {
    stat(scene == .active ? measurements : nil, t("measurements", "Confirmed records"))
    stat(scene == .active ? counts?.camera : nil, t("camera_count", "Camera originals"))
    stat(scene == .active ? counts?.uploaded : nil, t("upload_count", "Uploaded files"))
  }

  private func stat(_ value: Int?, _ title: String) -> some View {
    VStack(spacing: 3) {
      Text(value?.formatted() ?? "\u{2014}").font(.title3.bold()).monospacedDigit()
      Text(title).font(.caption).foregroundColor(.secondary)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var actions: some View {
    Group {
      if typeSize.isAccessibilitySize { VStack(spacing: 8) { actionButtons } }
      else { HStack(spacing: 8) { actionButtons } }
    }
  }

  @ViewBuilder private var actionButtons: some View {
    Button { menu = .imports } label: {
      Label(t("import", "Import"), systemImage: "square.and.arrow.down")
        .frame(maxWidth: .infinity, minHeight: 44)
    }.buttonStyle(.borderedProminent).tint(.green).foregroundColor(.black)
    Button { menu = .exports } label: {
      Label(t("export", "Export"), systemImage: "square.and.arrow.up")
        .frame(maxWidth: .infinity, minHeight: 44)
    }.buttonStyle(.bordered)
  }

  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        heading(t("recent", "Recent files"))
        Spacer(minLength: 8)
        NavigationLink(t("all", "View all")) { GalaxySSIHealthOriginalsView(store: store) }
          .frame(minHeight: 44)
      }
      VStack(spacing: 0) {
        if scene == .active, let recent, !recent.isEmpty {
          ForEach(recent) { item in
            Button { show(.original(item.reference)) } label: { fileRow(item) }.buttonStyle(.plain)
            if item.id != recent.last?.id { Divider() }
          }
        } else {
          Text(failed ? t("failed", "Health files could not be loaded.") :
            (recent == nil ? t("loading", "Loading recent files...") : t("empty", "No original files yet.")))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
          if failed { Button(t("retry", "Try again"), action: reload).padding(.bottom, 12) }
        }
      }.background(panel)
    }
  }

  private func fileRow(_ item: GalaxySSIHealthDataFiles.Recent) -> some View {
    let original = item.original
    let kind = original.kind == .pdf ? "PDF" : original.fileExtension.uppercased()
    let size = ByteCountFormatter.string(fromByteCount: Int64(original.bytes), countStyle: .file)
    let source: String
    switch original.acquisition {
    case .camera: source = t("camera", "Camera")
    case .uploaded: source = t("uploaded", "Upload")
    case nil: source = t("unknown", "Unknown source")
    }
    let status: String
    switch item.status {
    case .linked: status = t("linked", "Linked")
    case .unlinked: status = t("unlinked", "Unlinked")
    case .unavailable: status = t("unavailable", "Original unavailable")
    }
    return manage(original.name, [kind + " " + size, source, status].joined(separator: " \u{00B7} "),
                  icon: original.kind == .pdf ? "doc.text" : "photo", accent: .blue)
  }

  private func heading(_ text: String, size: Font = .headline) -> some View {
    Text(text).font(size.bold()).accessibilityAddTraits(.isHeader)
  }

  private func manage(_ title: String, _ detail: String, icon: String, accent: Color) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon).foregroundColor(accent).frame(width: 36, height: 36)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.body.weight(.semibold))
        Text(detail).font(.caption).foregroundColor(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(.secondary)
        .accessibilityHidden(true)
    }
    .padding(12)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var panel: some View {
    RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemGroupedBackground))
  }

  private var menuTitle: String {
    switch menu {
    case .imports: return t("import", "Import")
    case .exports: return t("export", "Export")
    case .tasks: return t("tasks", "Import and export tasks")
    case .backup: return t("backup", "Backup and restore")
    case nil: return ""
    }
  }

  @ViewBuilder private var menuActions: some View {
    switch menu {
    case .imports:
      option(t("import_records", "Import measurements"), .measurementsImport)
      option(t("import_originals", "Import originals"), .originalsImport)
    case .exports:
      option(t("export_records", "Export measurements"), .measurementsExport)
      option(t("export_originals", "Export originals"), .originalsExport)
    case .tasks:
      option(t("review", "Import review queue"), .review)
      option(t("table_history", "Table import history"), .tableHistory)
      option(t("export_history", "Measurement export history"), .measurementsHistory)
      option(t("originals_history", "Original export history"), .originalsHistory)
    case .backup:
      option(t("backup_create", "Create encrypted backup"), .backup(.create))
      option(t("backup_history", "Backup history"), .backup(.history))
      option(t("backup_verify", "Verify a backup"), .backup(.verify))
      option(t("backup_restore", "Restore from backup"), .backup(.restore))
    case nil: EmptyView()
    }
  }

  private func option(_ title: String, _ route: Route) -> some View { Button(title) { show(route) } }

  @ViewBuilder private var destination: some View {
    switch route {
    case .measurementsImport: GalaxySSIHealthImportView(store: store, records: records)
    case .originalsImport: GalaxySSIHealthOriginalsView(store: store, pickOnAppear: true)
    case .measurementsExport: GalaxySSIHealthMeasurementExportView(records: records)
    case .originalsExport: GalaxySSIHealthOriginalsView(store: store)
    case .review: review()
    case .tableHistory: GalaxySSIHealthTableImportView(records: records)
    case .measurementsHistory: GalaxySSIHealthMeasurementExportHistoryView(records: records)
    case .originalsHistory: OriginalExportHistory(store: store)
    case .backup(let entry): GalaxySSIHealthBackupView(records: records, originals: store, entry: entry)
    case .original(let reference): GalaxySSIHealthOriginalsView(store: store, exact: reference)
    case nil: EmptyView()
    }
  }

  private func show(_ route: Route) {
    guard scene == .active else { return }
    menu = nil
    self.route = route
    navigating = true
  }

  private func clear() {
    if !restoreOffset, let view = scroll.view { offset = Double(view.contentOffset.y) }
    restoreOffset = true
    request?.cancel()
    request = nil
    recent = nil
    measurements = nil
    counts = nil
    failed = false
    menu = nil
  }

  private func reload() {
    guard visible, scene == .active else { return }
    request?.cancel()
    request = Task {
      do {
        let reader = try records.dataFilesReader()
        let directory = try store.dataFilesDirectory()
        var snapshot = try await Self.read(reader)
        try Task.checkCancellation()
        if snapshot.originals == nil {
          let legacy = try await Self.readLegacy(store.legacyDataFilesReader(directory: directory))
          // Migration can commit while the legacy headers are being read.
          snapshot = try await Self.read(records.dataFilesReader())
          if snapshot.originals == nil { snapshot.originals = legacy }
        }
        let rows = try await Self.recent(snapshot, directory: directory)
        try Task.checkCancellation()
        recent = rows
        measurements = snapshot.measurements
        failed = false
        restoreScroll()
        let result = try await snapshot.counts()
        try Task.checkCancellation()
        counts = result
      } catch {
        guard !Task.isCancelled else { return }
        recent = nil
        measurements = nil
        counts = nil
        failed = true
      }
    }
  }

  nonisolated private static func read(_ reader: GalaxySSIHealthDataFiles.Reader) async throws
    -> GalaxySSIHealthDataFiles.Snapshot { try reader.read() }

  nonisolated private static func recent(_ snapshot: GalaxySSIHealthDataFiles.Snapshot, directory: URL) async throws
    -> [GalaxySSIHealthDataFiles.Recent] { try snapshot.recent(in: directory) }

  nonisolated private static func readLegacy(_ reader: GalaxySSIHealthOriginalStore.LegacyIndexReader) async throws
    -> [GalaxySSIHealthDataFiles.Original] { try GalaxySSIHealthDataFiles.active(reader.read()) }

  private func restoreScroll() {
    guard restoreOffset else { return }
    DispatchQueue.main.async {
      guard visible, scene == .active, recent != nil, restoreOffset, let view = scroll.view else { return }
      view.layoutIfNeeded()
      let minimum = -view.adjustedContentInset.top
      let maximum = max(minimum, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
      view.setContentOffset(CGPoint(x: view.contentOffset.x, y: min(max(CGFloat(offset), minimum), maximum)),
                            animated: false)
      restoreOffset = false
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.data_files." + key, fallback: fallback, language: language)
  }

  private final class ScrollReference { weak var view: UIScrollView? }

  private struct ScrollResolver: UIViewRepresentable {
    let reference: ScrollReference

    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.isUserInteractionEnabled = false
      return view
    }

    func updateUIView(_ view: UIView, context: Context) {
      DispatchQueue.main.async {
        var ancestor = view.superview
        while let current = ancestor {
          if let scroll = current as? UIScrollView { reference.view = scroll; return }
          ancestor = current.superview
        }
      }
    }
  }
}

@MainActor
struct GalaxySSIHealthMeasurementExportHistoryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  @State private var receipts: [GalaxySSIHealthMeasurementExport.Receipt]?

  var body: some View {
    List {
      if scene == .active {
        if let receipts {
          if receipts.isEmpty {
            Text(t("no_exports", "No measurement exports yet.")).foregroundColor(.secondary)
          }
          ForEach(receipts) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.format.rawValue.uppercased() + (item.includesOriginals ? " + ZIP" : ""))
                .font(.headline)
              Text(item.at, style: .date)
              Text(String(format: t("export_rows", "%lld confirmed records"), Int64(item.rows)))
              Text(status(item.status))
            }.accessibilityElement(children: .combine)
          }
        } else {
          Text(t("failed", "Health files could not be loaded."))
          Button(t("retry", "Try again"), action: reload)
        }
      }
    }
    .navigationTitle(t("export_history", "Measurement export history"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear { receipts = nil }
    .onChange(of: scene) { _ in reload() }
  }

  private func reload() {
    guard scene == .active else { receipts = nil; return }
    do { receipts = Array((try records.load().measurementExports ?? []).reversed()) }
    catch { receipts = nil }
  }

  private func status(_ value: GalaxySSIHealthMeasurementExport.Receipt.Status) -> String {
    switch value {
    case .prepared: return t("export_prepared", "Prepared, save not confirmed")
    case .verified: return t("export_verified", "Saved and verified")
    case .unverified: return t("export_unverified", "Save not verified")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.data_files." + key, fallback: fallback, language: language)
  }
}
