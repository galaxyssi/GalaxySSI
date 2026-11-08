import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthPhotoCaptureView: View {
  private struct Capture: Identifiable {
    var id = UUID()
    let version: UUID?
    let mode: GalaxySSIHealthPhotoDraft.Mode
    let replacement: UUID?
    let acquisition: GalaxySSIHealthOriginalStore.Acquisition
  }

  let records: GalaxySSIHealthRecords
  let originals: GalaxySSIHealthOriginalStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var draft: GalaxySSIHealthPhotoDraft.Batch?
  @State private var mode = GalaxySSIHealthPhotoDraft.Mode.report
  @State private var camera: Capture?
  @State private var gallery: Capture?
  @State private var cropOriginal: GalaxySSIHealthOriginalStore.Original?
  @State private var generation = UUID()
  @State private var staging = false
  @State private var stagingTask: Task<Void, Never>?
  @State private var confirmingDiscard = false
  @State private var submittedBatchID: UUID?
  @State private var failed = false
  @State private var loaded = false

  var body: some View {
    List {
      if scene == .active {
        Section(t("collection", "Photo collection")) {
          Picker(t("mode", "Capture mode"), selection: $mode) {
            Text(t("report", "Report")).tag(GalaxySSIHealthPhotoDraft.Mode.report)
            Text(t("device", "Device reading")).tag(GalaxySSIHealthPhotoDraft.Mode.device)
          }.disabled(draft != nil || staging)
          Button { start(.camera) } label: {
            Label(t("take", "Take and keep photo"), systemImage: "camera")
          }.disabled(!canAdd)
          Button { start(.uploaded) } label: {
            Label(t("album", "Choose and keep photo"), systemImage: "photo.on.rectangle")
          }.disabled(!canAdd)
          if staging { ProgressView() }
        }
        if let draft, !draft.pages.isEmpty {
          Section(t("pages", "Pages in order")) {
            ForEach(Array(draft.pages.enumerated()), id: \.element.id) { index, page in
              row(page, index: index, draft: draft)
            }
          }
          Section {
            Button {
              do {
                try records.submitPhotoCaptureDraft(expected: draft.version, originals: originals)
                submittedBatchID = draft.id
                reload()
              } catch { failed = true }
            } label: {
              Label(t("submit", "Queue photos for recognition"), systemImage: "text.viewfinder")
            }
            .disabled(staging)
            Button(t("discard", "Discard collection"), role: .destructive) { confirmingDiscard = true }
              .disabled(staging)
          }
        } else if let draft {
          Button(t("discard", "Discard collection"), role: .destructive) {
            edit(draft, page: nil)
          }.disabled(staging)
        }
        if let submittedBatchID {
          NavigationLink {
            GalaxySSIHealthRecognitionJobsView(records: records, store: originals, automaticPhotoBatch: submittedBatchID)
          } label: {
            Label(t("queued", "Open queued recognition jobs"), systemImage: "text.viewfinder")
          }
        }
        if failed {
          Text(t("failed", "The photo collection could not be updated. Check the originals and try again."))
            .foregroundColor(.secondary)
          Button(t("reload", "Reload collection"), action: reload)
        }
      }
    }
    .navigationTitle(t("title", "Health photos"))
    .navigationBarTitleDisplayMode(.inline)
    .privacySensitive()
    .onAppear(perform: reload)
    .onDisappear {
      if camera == nil && gallery == nil && cropOriginal == nil { clearTransient() }
    }
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else if $0 == .background { clearTransient() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clearTransient() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notice in
      if notice.object as? String == records.owner { reload() }
    }
    .fullScreenCover(item: $camera) { request in
      GalaxySSIHealthPhotoCamera(title: t("title", "Health photos"), t: t) {
        if camera?.id == request.id { stage($0, request: request) }
      }
    }
    .sheet(item: $cropOriginal) { original in
      NavigationView {
        GalaxySSIHealthReportCropView(store: originals, initialOriginalID: original.id)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button(t("close", "Close")) { cropOriginal = nil }
            }
          }
      }.navigationViewStyle(.stack)
    }
    .sheet(item: $gallery) { request in
      GalaxySSIHealthPhotoAlbum { data in
        guard gallery?.id == request.id else { return }
        gallery = nil
        if let data { stage(data, request: request) }
      }
      .ignoresSafeArea()
    }
    .confirmationDialog(t("discard", "Discard collection"), isPresented: $confirmingDiscard,
      titleVisibility: .visible) {
      Button(t("discard", "Discard collection"), role: .destructive) {
        if let draft { edit(draft, page: nil) }
      }
    } message: {
      Text(t("keep_originals", "Saved originals remain in Health Originals."))
    }
  }

  private var canAdd: Bool {
    loaded && !staging && (draft?.pages.count ?? 0) < GalaxySSIHealthPhotoDraft.maximumPages
  }

  private func row(_ page: GalaxySSIHealthPhotoDraft.Entry, index: Int, draft: GalaxySSIHealthPhotoDraft.Batch) -> some View {
    HStack(spacing: 10) {
      GalaxySSIHealthPhotoThumbnail(original: page.original, store: originals)
      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: t("page", "Page %lld"), Int64(index + 1))).font(.headline)
        ForEach(page.hints, id: \.rawValue) { hint in
          Text(qualityHint(hint)).font(.caption).foregroundColor(.secondary)
        }
      }
      Spacer(minLength: 4)
      Menu {
        Button { edit(draft, page: page.id, offset: -1) } label: {
          Label(t("up", "Move earlier"), systemImage: "arrow.up")
        }.disabled(index == 0)
        Button { edit(draft, page: page.id, offset: 1) } label: {
          Label(t("down", "Move later"), systemImage: "arrow.down")
        }.disabled(index + 1 == draft.pages.count)
        Button { start(.camera, replacing: page.id) } label: {
          Label(t("retake", "Retake page"), systemImage: "camera")
        }
        Button {
          cropOriginal = page.original
        } label: { Label(t("crop", "Crop page"), systemImage: "crop") }
        Button(role: .destructive) { edit(draft, page: page.id) } label: {
          Label(t("remove", "Remove page"), systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis").frame(width: 44, height: 44)
      }.disabled(staging)
    }
  }

  private func start(_ acquisition: GalaxySSIHealthOriginalStore.Acquisition, replacing: UUID? = nil) {
    guard scene == .active, loaded, !staging, originals.owner == records.owner else { return }
    let request = Capture(version: draft?.version, mode: draft?.mode ?? mode, replacement: replacing,
      acquisition: acquisition)
    if acquisition == .camera { camera = request } else { gallery = request }
  }

  private func stage(_ data: Data, request: Capture) {
    guard scene == .active, !staging, loaded, draft?.version == request.version else { return }
    staging = true; failed = false; submittedBatchID = nil
    let token = generation
    stagingTask = Task {
      let inspector = Task.detached(priority: .userInitiated) { try GalaxySSIHealthPhotoDraft.inspect(data) }
      do {
        let hints = try await withTaskCancellationHandler(operation: { try await inspector.value },
          onCancel: { inspector.cancel() })
        guard !Task.isCancelled, generation == token, scene == .active else {
          if generation == token { staging = false; stagingTask = nil }
          return
        }
        let name = "Health-Photo-" + String(UUID().uuidString.prefix(8))
        try originals.storePhotoCapturePage(data, name: name, acquisition: request.acquisition, mode: request.mode,
          expected: request.version, replacing: request.replacement, hints: hints)
        reload()
      } catch {
        if !Task.isCancelled, generation == token { failed = true }
      }
      if generation == token { staging = false; stagingTask = nil }
    }
  }

  private func edit(_ draft: GalaxySSIHealthPhotoDraft.Batch, page: UUID?, offset: Int? = nil) {
    guard scene == .active, !staging else { return }
    do { try records.editPhotoCaptureDraft(expected: draft.version, page: page, offset: offset); reload() }
    catch { failed = true }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      draft = try records.load().photoCaptureDraft
      if let draft { mode = draft.mode }
      loaded = true; failed = false
    } catch { draft = nil; loaded = false; failed = true }
  }

  private func clearTransient() {
    generation = UUID()
    stagingTask?.cancel(); stagingTask = nil
    camera = nil; gallery = nil; cropOriginal = nil; draft = nil
    staging = false; loaded = false; confirmingDiscard = false
    submittedBatchID = nil; failed = false
  }

  private func qualityHint(_ hint: GalaxySSIHealthPhotoDraft.Hint) -> String {
    switch hint {
    case .small: return t("small", "May be too small to read")
    case .dark: return t("dark", "May be too dark")
    case .glare: return t("glare", "May have glare")
    case .lowDetail: return t("detail", "May be blurred")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.photo_capture." + key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIHealthPhotoThumbnail: View {
  let original: GalaxySSIHealthOriginalStore.Original
  let store: GalaxySSIHealthOriginalStore
  @State private var image: CGImage?
  @Environment(\.scenePhase) private var scene

  var body: some View {
    Group {
      if scene == .active, let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      else { Image(systemName: "photo") }
    }
    .frame(width: 52, height: 52)
    .task(id: original.id) {
      if scene == .active, let data = try? store.read(original) {
        image = GalaxySSIHealthPhotoDraft.thumbnail(data, maximum: 144)
      }
    }
    .onDisappear { image = nil }
  }
}

private struct GalaxySSIHealthPhotoAlbum: UIViewControllerRepresentable {
  let onData: (Data?) -> Void

  func makeCoordinator() -> Coordinator { .init(onData: onData) }
  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 1
    configuration.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = context.coordinator
    return picker
  }
  func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let onData: (Data?) -> Void
    init(onData: @escaping (Data?) -> Void) { self.onData = onData }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      guard let provider = results.first?.itemProvider,
            let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true })
      else { onData(nil); return }
      provider.loadFileRepresentation(forTypeIdentifier: type) { [onData] url, _ in
        var data: Data?
        if let url, let handle = try? FileHandle(forReadingFrom: url) {
          defer { try? handle.close() }
          let maximum = GalaxySSIHealthOriginalStore.maximumFileBytes
          let bytes = try? handle.read(upToCount: maximum + 1)
          if let bytes, (1...maximum).contains(bytes.count) { data = bytes }
        }
        DispatchQueue.main.async { onData(data) }
      }
    }
  }
}
