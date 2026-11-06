import SwiftUI
import UIKit

enum GalaxySSIComposerTrayActionID: String, CaseIterable, Identifiable {
  case newSession = "new-session"
  case sessions
  case scan
  case camera
  case file
  case screenshot

  var id: String { rawValue }
}

struct GalaxySSIComposerTrayAction: Identifiable {
  var id: GalaxySSIComposerTrayActionID
  var title: String
  var systemImage: String
  var perform: () -> Void

  var iconTint: Color {
    switch id {
    case .newSession:
      return Color(red: 16 / 255, green: 175 / 255, blue: 104 / 255)
    case .sessions:
      return Color(red: 119 / 255, green: 87 / 255, blue: 215 / 255)
    case .scan:
      return Color(red: 77 / 255, green: 111 / 255, blue: 245 / 255)
    case .camera:
      return Color(red: 230 / 255, green: 135 / 255, blue: 43 / 255)
    case .file, .screenshot:
      return Color(red: 24 / 255, green: 167 / 255, blue: 189 / 255)
    }
  }
}

struct GalaxySSIComposerActionTray: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var actions: [GalaxySSIComposerTrayAction]
  var accessibilityPrefix: String
  var minimumTouchSize: CGFloat
  var onSelect: () -> Void

  var body: some View {
    Group {
      if usesAccessibilityDynamicType {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3),
          spacing: 0
        ) {
          trayButtons
        }
        .frame(height: 176)
      } else {
        HStack(spacing: 0) {
          trayButtons
        }
        .frame(height: 96)
      }
    }
    .background(Color.galaxySSIBarBackground)
  }

  @ViewBuilder
  private var trayButtons: some View {
    ForEach(actions) { item in
      Button {
        onSelect()
        item.perform()
      } label: {
        VStack(spacing: 6) {
          Image(systemName: item.systemImage)
            .font(.system(size: 23, weight: .semibold))
            .foregroundColor(item.iconTint)
            .frame(width: 46, height: 46)
            .overlay(
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(item.iconTint, lineWidth: 2)
            )
          Text(item.title)
            .font(.system(size: usesAccessibilityDynamicType ? 13 : 12))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .minimumScaleFactor(usesAccessibilityDynamicType ? 0.85 : 0.72)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: minimumTouchSize)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(item.title))
      .accessibilityIdentifier("\(accessibilityPrefix).\(item.id.rawValue)")
    }
  }

  private var usesAccessibilityDynamicType: Bool {
    switch dynamicTypeSize {
    case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
      return true
    default:
      return false
    }
  }
}

struct GalaxySSIComposerMoreButtonIcon: View {
  var expanded: Bool

  var body: some View {
    ZStack {
      if expanded {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(Color.galaxySSIButtonSoft)
          .frame(width: 32, height: 32)

        Capsule()
          .fill(Color.galaxySSITextPrimary)
          .frame(width: 12, height: 2.25)
      } else {
        Image(systemName: "square.3.layers.3d")
          .font(.system(size: 22, weight: .medium))
          .foregroundColor(.galaxySSITextPrimary)
      }
    }
    .frame(width: 46, height: 46)
  }
}

struct GalaxySSIComposerVoiceButtonIcon: View {
  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      Circle()
        .frame(width: 4, height: 4)
      Capsule()
        .frame(width: 4, height: 12)
      Capsule()
        .frame(width: 4, height: 22)
      Capsule()
        .frame(width: 4, height: 12)
      Circle()
        .frame(width: 4, height: 4)
    }
    .foregroundColor(.galaxySSITextPrimary)
    .frame(width: 46, height: 46)
  }
}

private struct GalaxySSIComposerTextHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 54

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

struct GalaxySSIGrowingComposerEditor: View {
  @Environment(\.scenePhase) private var scenePhase
  @Binding var text: String
  var placeholder: String
  var focus: FocusState<Bool>.Binding
  var accessibilityIdentifier: String
  var onTap: () -> Void
  var attachmentScope = ""
  var onImageAttachment: ((GalaxySSIDraftAttachment) -> Void)? = nil
  @State private var clipboardImage: ClipboardImage?

  private struct ClipboardImage: Identifiable {
    let id = UUID()
    let scope: String
    let data: Data
  }

  @State private var editorHeight: CGFloat = 54

  private let minimumHeight: CGFloat = 54
  private let maximumHeight: CGFloat = 172

  var body: some View {
    ZStack(alignment: .topLeading) {
      Text(text.isEmpty ? " " : text + "\n")
        .font(.system(size: 15))
        .foregroundColor(.clear)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: GalaxySSIComposerTextHeightKey.self,
              value: proxy.size.height
            )
          }
        )

      if text.isEmpty {
        Text(placeholder)
          .font(.system(size: 15))
          .foregroundColor(.galaxySSITextSecondary)
          .padding(.leading, 12)
          .padding(.top, 16)
          .allowsHitTesting(false)
      }

      GalaxySSIParagraphSelectingTextView(
        text: $text,
        focus: focus,
        editingScope: attachmentScope,
        accessibilityIdentifier: accessibilityIdentifier,
        onBeginEditing: onTap,
        onImagePaste: onImageAttachment == nil ? nil : {
          guard scenePhase == .active, !attachmentScope.isEmpty, let data = GalaxySSIImageClipboard.read() else { return }
          clipboardImage = ClipboardImage(scope: attachmentScope, data: data)
        }
      )
    }
    .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: editorHeight)
    .onPreferenceChange(GalaxySSIComposerTextHeightKey.self) { measuredHeight in
      editorHeight = min(max(measuredHeight, minimumHeight), maximumHeight)
    }
    .sheet(item: $clipboardImage) { pending in
      GalaxySSIClipboardImageReview(data: pending.data) { attachment in
        guard scenePhase == .active, pending.scope == attachmentScope, clipboardImage?.id == pending.id else { return }
        onImageAttachment?(attachment)
      }
    }
    .onChange(of: attachmentScope) { _ in clipboardImage = nil }
    .onChange(of: scenePhase) { if $0 != .active { clipboardImage = nil } }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clipboardImage = nil }
    .onDisappear { clipboardImage = nil }
  }
}

enum GalaxySSIParagraphSelectionPolicy {
  @MainActor
  static func glyphOffset(at point: CGPoint, in textView: UITextView) -> Int? {
    let layout = textView.layoutManager
    let container = textView.textContainer
    layout.ensureLayout(for: container)
    guard layout.numberOfGlyphs > 0 else { return nil }
    let inset = textView.textContainerInset
    let local = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
    let index = layout.glyphIndex(for: local, in: container)
    guard index < layout.numberOfGlyphs else { return nil }
    let glyph = NSRange(location: index, length: 1)
    guard layout.boundingRect(forGlyphRange: glyph, in: container).contains(local) else { return nil }
    let range = layout.characterRange(forGlyphRange: glyph, actualGlyphRange: nil)
    let text = (textView.text ?? "") as NSString
    guard range.length > 0, NSMaxRange(range) <= text.length,
          !text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return range.location
  }

  static func expansion(in text: String, glyphOffset: Int, nativeSelection: NSRange) -> NSRange? {
    let length = (text as NSString).length
    guard glyphOffset >= 0, glyphOffset < length, nativeSelection.location >= 0, nativeSelection.location <= length,
          nativeSelection.length > 0, nativeSelection.length <= length - nativeSelection.location,
          NSLocationInRange(glyphOffset, nativeSelection) else { return nil }
    let paragraph = range(in: text, requestedUTF16Offset: glyphOffset)
    return paragraph.length > nativeSelection.length &&
      NSEqualRanges(NSIntersectionRange(paragraph, nativeSelection), nativeSelection) ? paragraph : nil
  }

  static func range(in text: String, requestedUTF16Offset: Int) -> NSRange {
    let source = text as NSString
    guard source.length > 0 else { return NSRange(location: 0, length: 0) }

    var anchor = min(max(requestedUTF16Offset, 0), source.length)
    if anchor == source.length {
      anchor -= 1
    }
    if source.character(at: anchor) == 10, anchor > 0 {
      anchor -= 1
    }

    var start = 0
    for index in stride(from: anchor, through: 0, by: -1) where source.character(at: index) == 10 {
      start = index + 1
      break
    }

    var end = source.length
    for index in anchor..<source.length where source.character(at: index) == 10 {
      end = index
      break
    }
    if end > start, source.character(at: end - 1) == 13 {
      end -= 1
    }
    return NSRange(location: start, length: max(end - start, 0))
  }
}

private struct GalaxySSIParagraphSelectingTextView: UIViewRepresentable {
  @Binding var text: String
  var focus: FocusState<Bool>.Binding
  var editingScope: String
  var accessibilityIdentifier: String
  var onBeginEditing: () -> Void
  var onImagePaste: (() -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = GalaxySSIImagePastingTextView()
    textView.onImagePaste = onImagePaste
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.font = .systemFont(ofSize: 15)
    textView.textColor = UIColor(Color.galaxySSITextPrimary)
    textView.autocapitalizationType = .sentences
    textView.autocorrectionType = .default
    textView.keyboardDismissMode = .interactive
    textView.isEditable = true
    textView.isSelectable = true
    textView.isScrollEnabled = true
    textView.textContainer.lineFragmentPadding = 0
    textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
    textView.accessibilityIdentifier = accessibilityIdentifier

    let longPress = UILongPressGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.selectParagraph(_:))
    )
    longPress.cancelsTouchesInView = false
    longPress.delaysTouchesEnded = false
    longPress.allowableMovement = 10
    longPress.delegate = context.coordinator
    textView.addGestureRecognizer(longPress)
    let blankTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.showBlankTapMenu(_:)))
    blankTap.cancelsTouchesInView = false
    blankTap.delaysTouchesEnded = false
    blankTap.delegate = context.coordinator
    textView.addGestureRecognizer(blankTap)
    context.coordinator.paragraphPress = longPress
    context.coordinator.textView = textView
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    if context.coordinator.parent.editingScope != editingScope {
      context.coordinator.cancelPendingEdits()
    }
    context.coordinator.parent = self
    (textView as? GalaxySSIImagePastingTextView)?.onImagePaste = onImagePaste
    if textView.text != text {
      context.coordinator.cancelPendingEdits()
      let selection = textView.selectedRange
      textView.text = text
      let textLength = (text as NSString).length
      let location = min(selection.location, textLength)
      textView.selectedRange = NSRange(
        location: location,
        length: min(selection.length, textLength - location)
      )
    }
    textView.accessibilityIdentifier = accessibilityIdentifier
    if focus.wrappedValue, !textView.isFirstResponder {
      textView.becomeFirstResponder()
    } else if !focus.wrappedValue, textView.isFirstResponder {
      context.coordinator.cancelPendingEdits()
      textView.resignFirstResponder()
    }
  }

  static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
    coordinator.cancelPendingEdits()
    coordinator.textView = nil
    textView.delegate = nil
  }

  final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var parent: GalaxySSIParagraphSelectingTextView
    weak var textView: UITextView?
    weak var paragraphPress: UILongPressGestureRecognizer?
    private var pressStart: CGPoint?
    private var pressedGlyph: Int?
    private var blankTapStart: CGPoint?
    private var pendingEdit: DispatchWorkItem?
    private var gestureGeneration: UInt64 = 0

    init(parent: GalaxySSIParagraphSelectingTextView) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      cancelPendingEdits()
      parent.text = textView.text
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.focus.wrappedValue = true
      parent.onBeginEditing()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      cancelPendingEdits()
      parent.focus.wrappedValue = false
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
      cancelPendingEdits()
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard let textView, textView.isFirstResponder, textView.markedTextRange == nil else { return false }
      guard recognizer.numberOfTouches == 0 else {
        cancelPendingEdits()
        return false
      }
      let point = touch.location(in: textView)
      let glyph = GalaxySSIParagraphSelectionPolicy.glyphOffset(at: point, in: textView)
      cancelScheduledEdit()
      if recognizer === paragraphPress {
        pressStart = glyph == nil ? nil : point
        pressedGlyph = glyph
        return glyph != nil
      }
      blankTapStart = glyph == nil ? point : nil
      return glyph == nil
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    @objc func selectParagraph(_ gesture: UILongPressGestureRecognizer) {
      switch gesture.state {
      case .began:
        guard let pressedGlyph, let textView else { return }
        let original = textView.text ?? ""
        scheduleEdit(delay: 0.032) { [weak self, weak gesture] view in
          guard let self, let gesture, self.stationary(gesture, in: view),
                view.text == original,
                let range = GalaxySSIParagraphSelectionPolicy.expansion(
                  in: original, glyphOffset: pressedGlyph, nativeSelection: view.selectedRange) else { return }
          view.selectedRange = range
        }
      case .changed:
        if let textView, !stationary(gesture, in: textView) { cancelPendingEdits() }
      case .ended, .cancelled, .failed:
        cancelPendingEdits()
      default:
        break
      }
    }

    @objc func showBlankTapMenu(_ gesture: UITapGestureRecognizer) {
      guard gesture.state == .ended, let textView, let start = blankTapStart else { return }
      blankTapStart = nil
      let point = gesture.location(in: textView)
      guard hypot(point.x - start.x, point.y - start.y) <= 10,
            GalaxySSIParagraphSelectionPolicy.glyphOffset(at: point, in: textView) == nil else { return }
      let original = textView.text ?? ""
      scheduleEdit(delay: 0) { view in
        guard view.text == original, view.selectedRange.length == 0,
              let caret = view.selectedTextRange?.start else { return }
        let rect = view.caretRect(for: caret)
        guard !rect.isNull, !rect.isInfinite, view.bounds.intersects(rect) else { return }
        if #available(iOS 16.0, *) {
          let interaction: UIEditMenuInteraction
          if let native = view.interactions.compactMap({ $0 as? UIEditMenuInteraction }).first {
            interaction = native
          } else {
            interaction = UIEditMenuInteraction(delegate: nil)
            view.addInteraction(interaction)
          }
          interaction.presentEditMenu(with: .init(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.midY)))
        } else {
          UIMenuController.shared.showMenu(from: view, rect: rect)
        }
      }
    }

    private func stationary(_ gesture: UILongPressGestureRecognizer, in view: UITextView) -> Bool {
      guard let pressStart, gesture.numberOfTouches == 1,
            gesture.state == .began || gesture.state == .changed else { return false }
      let point = gesture.location(in: view)
      return hypot(point.x - pressStart.x, point.y - pressStart.y) <= gesture.allowableMovement
    }

    private func scheduleEdit(delay: TimeInterval, _ apply: @escaping (UITextView) -> Void) {
      pendingEdit?.cancel()
      gestureGeneration &+= 1
      let generation = gestureGeneration
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.gestureGeneration == generation, let view = self.textView,
              view.isFirstResponder, view.window != nil, view.markedTextRange == nil,
              view.panGestureRecognizer.state != .began, view.panGestureRecognizer.state != .changed else { return }
        self.pendingEdit = nil
        apply(view)
      }
      pendingEdit = work
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelPendingEdits() {
      cancelScheduledEdit()
      pressStart = nil
      pressedGlyph = nil
      blankTapStart = nil
    }

    private func cancelScheduledEdit() {
      gestureGeneration &+= 1
      pendingEdit?.cancel()
      pendingEdit = nil
    }
  }
}

enum GalaxySSIPeerComposerActionPolicy {
  static let actionIDs: [GalaxySSIComposerTrayActionID] = [.newSession, .sessions, .scan, .camera, .file]

  static func consumesBackAction(actionTrayPresented: Bool) -> Bool {
    actionTrayPresented
  }
}
