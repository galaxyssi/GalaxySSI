import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIHealthPhotoDraft: Codable, Equatable {
  enum Mode: String, Codable, CaseIterable { case report, device }
  struct Page: Codable, Equatable, Identifiable {
    var id = UUID()
    let original: GalaxySSIHealthOriginalStore.Original
    var useCrop = false
    var cropRevision: UUID?
    var width: Int?
    var height: Int?
  }

  static let maximumPages = 40
  var version: UUID?
  var mode = Mode.report
  var pages: [Page] = []
}

@MainActor
struct GalaxySSIHealthPhotoDraftView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let store: GalaxySSIHealthOriginalStore
  var retentionChoice = GalaxySSIHealthImportRetentionChoice.useDefault
  @State private var draft = GalaxySSIHealthPhotoDraft()
  @State private var camera = false
  @State private var picker = false
  @State private var galleryAfterCamera = false
  @State private var retaking: UUID?
  @State private var limit = 20
  @State private var failed = false
  @State private var submitted = false
  @State private var request: CaptureRequest?
  @State private var pendingRetention: CaptureRequest?
  @State private var confirmingRetention = false

  private struct CaptureRequest {
    let useCamera: Bool
    var version: UUID?
    let replacement: UUID?
  }

  var body: some View {
    List {
      if scene == .active {
        Section {
          Picker(t("mode", "Capture mode"), selection: Binding(get: { draft.mode }, set: { mode in
            change { $0.mode = mode }
          })) {
            Text(t("report", "Report")).tag(GalaxySSIHealthPhotoDraft.Mode.report)
            Text(t("device", "Device display")).tag(GalaxySSIHealthPhotoDraft.Mode.device)
          }.pickerStyle(.segmented)
          Button { prepareCapture(camera: true) } label: {
            Label(t("camera", "Take photo"), systemImage: "camera")
          }.disabled(draft.pages.count >= GalaxySSIHealthPhotoDraft.maximumPages)
          Button { prepareCapture(camera: false) } label: {
            Label(t("gallery", "Choose image files"), systemImage: "photo.on.rectangle")
          }.disabled(draft.pages.count >= GalaxySSIHealthPhotoDraft.maximumPages)
        }
        Section(t("pages", "Draft pages")) {
          ForEach(draft.pages.prefix(limit)) { page in row(page) }
          if draft.pages.count > limit { Button(t("more", "Show more pages")) { limit += 20 } }
          if draft.pages.isEmpty { Text(t("empty", "No draft pages")).foregroundColor(.secondary) }
        }
        Button(t("submit", "Queue pages for recognition"), action: submit).disabled(draft.pages.isEmpty)
        if submitted {
          NavigationLink {
            GalaxySSIHealthRecognitionJobsView(records: records, store: store)
          } label: { Text(t("queued", "Open queued recognition jobs")) }
        }
        if failed { Text(t("failed", "Could not prepare this page or save the draft.")) }
      }
    }
    .navigationTitle(t("title", "Health Photo Draft"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else if $0 == .background {
        camera = false; picker = false; draft = .init(); retaking = nil; request = nil
        pendingRetention = nil; confirmingRetention = false; galleryAfterCamera = false
      }
    }
    .confirmationDialog(t("retain_confirm", "Keep these original photos on this device?"),
                        isPresented: $confirmingRetention, titleVisibility: .visible,
                        presenting: pendingRetention) { request in
      Button(t("retain_continue", "Keep originals and continue")) { openCapture(request) }
    }
    .fullScreenCover(isPresented: $camera, onDismiss: {
      if galleryAfterCamera && scene == .active { picker = true }
      galleryAfterCamera = false
    }) {
      GalaxySSIHealthPhotoCamera(mode: draft.mode, shutterTitle: t("shutter", "Capture"),
        torchTitle: t("light", "Fill light"), closeTitle: t("close", "Close"),
        galleryTitle: t("gallery", "Choose image files"), onGallery: {
          galleryAfterCamera = true
          camera = false
        }, onClose: { camera = false; retaking = nil; request = nil }) { result in
          camera = false
          defer { retaking = nil; request = nil }
          do {
            var bytes = try result.get()
            defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
            guard scene == .active else { return }
            try append(bytes, name: "Health-Photo-" + String(UUID().uuidString.prefix(8)) + ".jpg", acquisition: .camera)
          } catch { failed = true }
        }
      .ignoresSafeArea()
    }
    .fileImporter(isPresented: $picker, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
      defer { retaking = nil; request = nil }
      guard scene != .background else { return }
      do {
        let urls = try result.get()
        guard urls.count <= (retaking == nil ? GalaxySSIHealthPhotoDraft.maximumPages - draft.pages.count : 1)
        else { throw GalaxySSIHealthOriginalStore.Failure.limit }
        for url in urls {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          let handle = try FileHandle(forReadingFrom: url)
          defer { try? handle.close() }
          var bytes = try handle.read(upToCount: GalaxySSIHealthOriginalStore.maximumFileBytes + 1) ?? Data()
          defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
          try append(bytes, name: url.lastPathComponent, acquisition: .uploaded)
        }
      } catch { failed = true }
    }
  }

  private func row(_ page: GalaxySSIHealthPhotoDraft.Page) -> some View {
    let index = draft.pages.firstIndex { $0.id == page.id } ?? 0
    return VStack(alignment: .leading, spacing: 6) {
      Text("\(index + 1) · \(page.original.name)").lineLimit(2)
      if let width = page.width, let height = page.height {
        Text(width > height ? t("landscape", "Landscape") : t("portrait", "Portrait"))
          .font(.subheadline).foregroundColor(.secondary)
        if min(width, height) < 720 { Text(t("resolution", "Low resolution")).foregroundColor(.secondary) }
      }
      NavigationLink {
        GalaxySSIHealthReportCropView(store: store, focusedOriginal: page.original)
      } label: { Label(t("crop", "Edit crop"), systemImage: "crop") }
      Toggle(t("use_crop", "Use saved crop for recognition"), isOn: Binding(get: { page.useCrop }, set: { enabled in
        chooseCrop(page, enabled: enabled)
      }))
      HStack {
        Button { move(index, to: index - 1) } label: { Image(systemName: "arrow.up") }
          .accessibilityLabel(t("up", "Move up")).disabled(index == 0)
        Button { move(index, to: index + 1) } label: { Image(systemName: "arrow.down") }
          .accessibilityLabel(t("down", "Move down")).disabled(index + 1 >= draft.pages.count)
        Spacer()
        Button { prepareCapture(camera: true, replacing: page.id) } label: { Image(systemName: "camera.rotate") }
          .accessibilityLabel(t("retake", "Retake"))
        Button(role: .destructive) { change { $0.pages.removeAll { $0.id == page.id } } } label: {
          Image(systemName: "trash")
        }.accessibilityLabel(t("remove", "Remove page"))
      }.buttonStyle(.borderless)
    }
  }

  private func chooseCrop(_ page: GalaxySSIHealthPhotoDraft.Page, enabled: Bool) {
    do {
      let crop = enabled ? try store.readCrop(for: page.original) : nil
      if enabled && crop == nil { throw GalaxySSIHealthRecords.Failure.stale }
      change { draft in
        if let row = draft.pages.firstIndex(where: { $0.id == page.id }) {
          draft.pages[row].useCrop = enabled
          draft.pages[row].cropRevision = crop?.metadata.revision
        }
      }
    } catch { failed = true }
  }

  private func prepareCapture(camera: Bool, replacing: UUID? = nil) {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      guard archive.photoDraft?.version == draft.version else { throw GalaxySSIHealthRecords.Failure.stale }
      let request = CaptureRequest(useCamera: camera, version: draft.version, replacement: replacing)
      if retentionChoice.resolve(default: archive.keepsNewImportOriginals) == true { openCapture(request) }
      else { pendingRetention = request; confirmingRetention = true }
    } catch { reload(); failed = true }
  }

  private func openCapture(_ next: CaptureRequest) {
    guard scene == .active, draft.version == next.version else { failed = true; return }
    request = next
    retaking = next.replacement
    failed = false
    if next.useCamera { camera = true } else { picker = true }
  }

  private func append(_ bytes: Data, name: String, acquisition: GalaxySSIHealthOriginalStore.Acquisition) throws {
    guard let request, request.version == draft.version, scene != .background,
          try records.load().photoDraft?.version == draft.version,
          !bytes.isEmpty, bytes.count <= GalaxySSIHealthOriginalStore.maximumFileBytes,
          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
    let original = try store.store(bytes, name: name, acquisition: acquisition)
    let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
    let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    let rotation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    var updated = draft
    let page = GalaxySSIHealthPhotoDraft.Page(original: original,
      width: (5...8).contains(rotation) ? height : width, height: (5...8).contains(rotation) ? width : height)
    if let retaking {
      guard let index = updated.pages.firstIndex(where: { $0.id == retaking }) else { throw GalaxySSIHealthRecords.Failure.stale }
      updated.pages[index] = page
    } else { updated.pages.append(page) }
    draft = try records.savePhotoDraft(updated)
    self.request?.version = draft.version
    retaking = nil; failed = false; submitted = false
  }

  private func move(_ index: Int, to destination: Int) {
    guard draft.pages.indices.contains(index), draft.pages.indices.contains(destination) else { return }
    change { $0.pages.swapAt(index, destination) }
  }

  private func change(_ action: (inout GalaxySSIHealthPhotoDraft) -> Void) {
    guard scene == .active else { return }
    var updated = draft
    action(&updated)
    do { draft = try records.savePhotoDraft(updated); failed = false }
    catch { reload(); failed = true }
  }

  private func submit() {
    guard scene == .active else { return }
    do { try records.submitPhotoDraft(draft, store: store); reload(); submitted = true }
    catch { reload(); failed = true }
  }

  private func reload() {
    guard scene == .active else { return }
    do { draft = try records.load().photoDraft ?? .init() }
    catch { failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.photo_draft." + key, fallback: fallback, language: language)
  }
}
