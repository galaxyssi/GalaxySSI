import SwiftUI
import UIKit

@MainActor
struct GalaxySSILocalMessageReader: View {
  typealias Search = GalaxySSILocalMessageSearch
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  let hit: Search.Hit
  let query: String
  @State private var lines: [Search.Line] = []
  @State private var older: GalaxySSIChatHistoryCursor?
  @State private var newer: GalaxySSIChatHistoryCursor?
  @State private var busy = true
  @State private var failed = false
  @State private var positioned = false
  @State private var readyToPosition = false
  @State private var request = Request()
  @State private var scroll = GalaxySSIChatScrollReference()
  @State private var anchor: Anchor?
  @State private var mounted = false
  @State private var viewportEpoch = GalaxySSIChatViewportEpoch()
  private struct Anchor { let id: UUID; let top: CGFloat }
  private struct Request: Equatable {
    var id = UUID()
    var older: GalaxySSIChatHistoryCursor?
    var newer: GalaxySSIChatHistoryCursor?
  }
  private var canRead: Bool {
    mounted && scene == .active && store.profile.identityFingerprint == hit.owner && UIApplication.shared.isProtectedDataAvailable &&
      store.canReadAgentTranscript && Search.allowed(hit.source, store: store)
  }
  var body: some View {
    NavigationView {
      ScrollViewReader { proxy in
        VStack(spacing: 0) {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
              if canRead {
                ForEach(lines) { line in
                  VStack(alignment: line.mine ? .trailing : .leading, spacing: 6) {
                    HStack { Text(line.at, style: .date); Text(line.at, style: .time) }
                      .font(.caption).foregroundColor(.secondary)
                    GalaxySSILocalMessageSearchText(text: ([line.text] + line.files).filter { !$0.isBlank }.joined(separator: "\n"),
                      query: line.id == hit.message ? query : "", position: { view, range in
                        positionMatch(view, range: range)
                      })
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(12)
                      .background(line.mine ? Color.galaxySSISentBubble : Color.galaxySSISurface)
                      .overlay(RoundedRectangle(cornerRadius: 6).stroke(line.id == hit.message ? Color.galaxySSIAccent : .clear, lineWidth: 1))
                  }
                  .frame(maxWidth: .infinity, alignment: line.mine ? .trailing : .leading)
                  .id(line.id)
                  .background(GeometryReader { geometry in
                    Color.clear.preference(key: GalaxySSIChatMessageFramesKey.self,
                      value: [line.id: geometry.frame(in: .named("local-message-reader"))])
                  })
                }
              }
              if busy { ProgressView().frame(maxWidth: .infinity) }
              if failed || !canRead { Text(t("gone", "This message is no longer available in ordinary history.")).foregroundColor(.secondary) }
            }
            .padding(12).background(GalaxySSIChatScrollResolver(reference: scroll))
          }
          .coordinateSpace(name: "local-message-reader")
          .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
            positioned = true; viewportEpoch.invalidate()
          })
          .onChange(of: lines.map(\.id)) { ids in
            guard !positioned, ids.contains(hit.message) else { return }
            let epoch = viewportEpoch.revision
            DispatchQueue.main.async {
              guard viewportEpoch.accepts(epoch), canRead, !positioned else { return }
              proxy.scrollTo(hit.message, anchor: .top); readyToPosition = true
            }
          }
          .onPreferenceChange(GalaxySSIChatMessageFramesKey.self) { frames in
            guard !busy, let view = scroll.view,
              let first = GalaxySSIChatMessageViewportPolicy.firstVisible(frames, height: view.bounds.height) else { return }
            anchor = Anchor(id: first.0, top: first.1)
          }
          HStack {
            if let older { Button(t("earlier", "Earlier messages")) { request = .init(older: older) } }
            Spacer(minLength: 8)
            if let newer { Button(t("later", "Later messages")) { request = .init(newer: newer) } }
          }
          .frame(minHeight: 44).padding(.horizontal, 12).disabled(busy || !canRead)
        }
        .task(id: request) { await load(proxy: proxy, request: request) }
      }
      .navigationTitle(canRead ? hit.source.title : "").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("back", "Back to search")) { dismiss() } } }
    }
    .navigationViewStyle(.stack)
    .privacySensitive()
    .onAppear { mounted = true; positioned = false; readyToPosition = false; anchor = nil; request = .init() }
    .onDisappear(perform: suspend)
    .onChange(of: scene) { if $0 != .active { suspend() } }
    .onChange(of: store.profile.identityFingerprint) { _ in suspend() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in suspend() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in suspend() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIWorkspaceDidPersist)) { _ in if !canRead { suspend() } }
  }
  private func clear() { lines = []; older = nil; newer = nil; busy = false; readyToPosition = false }
  private func suspend() { mounted = false; viewportEpoch.invalidate(); clear(); request = .init() }
  private func load(proxy: ScrollViewProxy, request job: Request) async {
    guard canRead else { clear(); return }
    busy = true; failed = false
    let retained = anchor
    let epoch = viewportEpoch.revision
    let conversations = store.agentConversationDatabase, messages = store.chatHistoryDatabase
    let worker = Task.detached(priority: .userInitiated) {
      try GalaxySSILocalMessageSearchScanner.context(hit, query: query, conversations: conversations, messages: messages,
        older: job.older, newer: job.newer)
    }
    do {
      let page = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
      guard !Task.isCancelled, request == job, canRead else { return }
      var seen: Set<UUID> = []
      lines = (job.older != nil ? page.lines + lines : lines + page.lines).filter { seen.insert($0.id).inserted }
      if job.newer == nil { older = page.older }
      if job.older == nil { newer = page.newer }
      busy = false
      guard viewportEpoch.accepts(epoch) else { return }
      if job.older == nil && job.newer == nil && !positioned {
        proxy.scrollTo(hit.message, anchor: .top)
        readyToPosition = true
      } else if let retained {
        proxy.scrollTo(retained.id, anchor: .top)
        DispatchQueue.main.async {
          guard request == job, canRead, viewportEpoch.accepts(epoch) else { return }
          scroll.adjustTop(by: -retained.top)
        }
      }
    } catch {
      guard !Task.isCancelled, request == job else { return }
      lines = []; busy = false; failed = true; older = nil; newer = nil
    }
  }
  private func positionMatch(_ view: UITextView, range: NSRange) {
    guard readyToPosition, !positioned, canRead, let scroll = scroll.view,
      !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating, view.bounds.width > 0 else { return }
    view.layoutManager.ensureLayout(for: view.textContainer)
    let glyphs = view.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    let rect = view.layoutManager.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
    let y = view.convert(CGPoint(x: rect.minX, y: rect.minY + view.textContainerInset.top), to: scroll).y
    let minY = -scroll.adjustedContentInset.top
    let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
    positioned = true
    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(maxY, max(minY, y - scroll.bounds.height / 3))), animated: false)
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.chat_search." + key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSILocalMessageSearchText: UIViewRepresentable {
  let text: String
  let query: String
  let position: (UITextView, NSRange) -> Void
  func makeUIView(context: Context) -> TextView {
    let view = TextView(); view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
    view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
    return view
  }
  func updateUIView(_ view: TextView, context: Context) {
    let font = UIFont.preferredFont(forTextStyle: .body)
    let value = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label])
    let range = query.isEmpty ? NSRange(location: NSNotFound, length: 0) : (text as NSString).range(of: query, options: .caseInsensitive)
    if range.location != NSNotFound { value.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: font.pointSize), range: range) }
    if view.attributedText?.isEqual(to: value) != true { view.attributedText = value; view.invalidateIntrinsicContentSize() }
    view.position = range.location == NSNotFound ? nil : { [weak view] in
      if let view { position(view, range) }
    }
    DispatchQueue.main.async { [weak view] in view?.position?() }
  }
  static func dismantleUIView(_ view: TextView, coordinator: ()) { view.position = nil; view.attributedText = nil }
  final class TextView: UITextView {
    var position: (() -> Void)?
    private var measuredWidth: CGFloat = 0
    override var intrinsicContentSize: CGSize {
      guard bounds.width > 0 else { return CGSize(width: UIView.noIntrinsicMetric, height: 1) }
      return CGSize(width: UIView.noIntrinsicMetric, height: sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
    }
    override func layoutSubviews() {
      super.layoutSubviews()
      if measuredWidth != bounds.width { measuredWidth = bounds.width; invalidateIntrinsicContentSize() }
      DispatchQueue.main.async { [weak self] in self?.position?() }
    }
  }
}
