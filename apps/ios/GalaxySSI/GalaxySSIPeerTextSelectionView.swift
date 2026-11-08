import SwiftUI
import UIKit

struct GalaxySSIPeerTextSelectionContext {
  var maximumWidth: CGFloat
  var onDelete: () -> Void
  var onMore: (() -> Void)? = nil
}

private struct GalaxySSIPeerTextSelectionKey: EnvironmentKey {
  static let defaultValue: GalaxySSIPeerTextSelectionContext? = nil
}

extension EnvironmentValues {
  var peerTextSelection: GalaxySSIPeerTextSelectionContext? {
    get { self[GalaxySSIPeerTextSelectionKey.self] }
    set { self[GalaxySSIPeerTextSelectionKey.self] = newValue }
  }
}

struct GalaxySSIPeerSelectableParagraphs: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
  var blocks: [AgentRichBlock]
  var selection: GalaxySSIPeerTextSelectionContext

  var body: some View {
    let text = GalaxySSIPeerTextRenderer.render(blocks, fontSize: fontSize)
    let size = GalaxySSIPeerTextRenderer.size(text, maximumWidth: selection.maximumWidth)
    GalaxySSIPeerTextSelectionView(text: text,
      deleteTitle: GalaxySSILocalization.string("galaxyssi.message.delete", fallback: "Delete Message", language: language),
      onDelete: selection.onDelete, onMore: selection.onMore,
      moreTitle: GalaxySSILocalization.string("galaxyssi.common.more", fallback: "More", language: language))
      .frame(width: size.width, height: size.height, alignment: .leading)
  }
}

struct GalaxySSIPeerSelectableTranscript: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ScaledMetric(relativeTo: .subheadline) private var fontSize: CGFloat = 14
  let text: String
  let messageID: UUID
  let outgoing: Bool
  let selection: GalaxySSIPeerTextSelectionContext

  var body: some View {
    let rendered = GalaxySSIPeerTextRenderer.transcript(text, fontSize: fontSize, outgoing: outgoing)
    let size = GalaxySSIPeerTextRenderer.size(rendered, maximumWidth: selection.maximumWidth)
    GalaxySSIPeerTextSelectionView(text: rendered,
      deleteTitle: GalaxySSILocalization.string("galaxyssi.message.delete", fallback: "Delete Message", language: language),
      onDelete: selection.onDelete, onMore: selection.onMore,
      moreTitle: GalaxySSILocalization.string("galaxyssi.common.more", fallback: "More", language: language),
      accessibilityID: "peer_voice_transcript_\(messageID.uuidString)")
      .frame(width: size.width, height: size.height, alignment: outgoing ? .trailing : .leading)
  }
}

struct GalaxySSIPeerTextSelectionView: UIViewRepresentable {
  var text: NSAttributedString
  var deleteTitle: String
  var onDelete: () -> Void
  var onMore: (() -> Void)? = nil
  var moreTitle = ""
  var accessibilityID = "ios.peer-message.selectable-text"

  func makeUIView(context: Context) -> GalaxySSIPeerSelectionTextView {
    let view = GalaxySSIPeerSelectionTextView()
    view.isEditable = false
    view.isSelectable = true
    view.isScrollEnabled = false
    view.backgroundColor = .clear
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.delegate = context.coordinator
    let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectParagraph(_:)))
    press.minimumPressDuration = 0.5
    press.allowableMovement = 10
    press.cancelsTouchesInView = false
    press.delegate = context.coordinator
    view.addGestureRecognizer(press)
    return view
  }

  func updateUIView(_ view: GalaxySSIPeerSelectionTextView, context: Context) {
    if view.attributedText?.isEqual(to: text) != true {
      view.attributedText = text
      view.selectedRange = NSRange(location: 0, length: 0)
    }
    view.onDeleteMessage = onDelete
    view.deleteTitle = deleteTitle
    view.onMoreMessage = onMore
    view.moreTitle = moreTitle
    view.accessibilityIdentifier = accessibilityID
  }

  static func dismantleUIView(_ view: GalaxySSIPeerSelectionTextView, coordinator: Coordinator) {
    view.onDeleteMessage = nil
    view.onMoreMessage = nil
    coordinator.cancelParagraphSelection()
    view.resignFirstResponder()
    view.clearLegacyMenu()
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    private var start: CGPoint?
    private var glyph: Int?
    private var paragraphSelection: DispatchWorkItem?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard gestureRecognizer.numberOfTouches == 0, let view = gestureRecognizer.view as? UITextView else { return false }
      cancelParagraphSelection()
      let point = touch.location(in: view)
      glyph = GalaxySSIParagraphSelectionPolicy.glyphOffset(at: point, in: view)
      start = glyph == nil ? nil : point
      return glyph != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    @objc func selectParagraph(_ press: UILongPressGestureRecognizer) {
      guard let view = press.view as? UITextView, let start, let glyph else { return }
      switch press.state {
      case .began:
        let original = view.text ?? ""
        let work = DispatchWorkItem { [weak view, weak press] in
          guard let view, let press, press.state == .began || press.state == .changed, view.text == original else { return }
          let point = press.location(in: view)
          guard hypot(point.x - start.x, point.y - start.y) <= 10,
                let range = GalaxySSIParagraphSelectionPolicy.expansion(in: original, glyphOffset: glyph,
                  nativeSelection: view.selectedRange) else { return }
          view.selectedRange = range
        }
        paragraphSelection = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
      case .changed:
        let point = press.location(in: view)
        if hypot(point.x - start.x, point.y - start.y) > 10 { cancelParagraphSelection() }
      case .ended, .cancelled, .failed:
        cancelParagraphSelection()
      default: break
      }
    }

    func cancelParagraphSelection() {
      paragraphSelection?.cancel()
      paragraphSelection = nil
      start = nil
      glyph = nil
    }

    @available(iOS 16.0, *)
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                  suggestedActions: [UIMenuElement]) -> UIMenu? {
      guard let view = textView as? GalaxySSIPeerSelectionTextView,
            range.length > 0 else { return nil }
      if view.onMoreMessage != nil {
        let more = UIAction(title: view.moreTitle, image: UIImage(systemName: "ellipsis")) { [weak view] _ in
          view?.showPeerMessageActions(nil)
        }
        return UIMenu(children: suggestedActions + [more])
      }
      guard view.onDeleteMessage != nil else { return nil }
      let delete = UIAction(title: view.deleteTitle, image: UIImage(systemName: "trash"),
        attributes: .destructive) { [weak view] _ in view?.delete(nil) }
      return UIMenu(children: suggestedActions + [delete])
    }
  }
}

final class GalaxySSIPeerSelectionTextView: UITextView {
  private static weak var legacyOwner: GalaxySSIPeerSelectionTextView?
  var onDeleteMessage: (() -> Void)?
  var onMoreMessage: (() -> Void)?
  var deleteTitle = ""
  var moreTitle = ""

  override func becomeFirstResponder() -> Bool {
    if #unavailable(iOS 16.0), onMoreMessage != nil {
      let menu = UIMenuController.shared
      let action = #selector(showPeerMessageActions(_:))
      let items = (menu.menuItems ?? []).filter { $0.action != action }
      Self.legacyOwner = self
      menu.menuItems = items + [UIMenuItem(title: moreTitle, action: action)]
    }
    let active = super.becomeFirstResponder()
    if !active { clearLegacyMenu() }
    return active
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { clearLegacyMenu() }
    return resigned
  }

  func clearLegacyMenu() {
    if #unavailable(iOS 16.0), Self.legacyOwner === self {
      Self.legacyOwner = nil
      let menu = UIMenuController.shared
      let items = (menu.menuItems ?? []).filter { $0.action != #selector(showPeerMessageActions(_:)) }
      menu.menuItems = items.isEmpty ? nil : items
    }
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(showPeerMessageActions(_:)) {
      return onMoreMessage != nil && selectedRange.length > 0
    }
    if action == #selector(UIResponderStandardEditActions.delete(_:)) {
      // Modern menus use the explicit destructive action; avoid a duplicate standard Delete.
      if #available(iOS 16.0, *) { return false }
      return onMoreMessage == nil && onDeleteMessage != nil && selectedRange.length > 0
    }
    if action == #selector(UIResponderStandardEditActions.cut(_:)) ||
        action == #selector(UIResponderStandardEditActions.paste(_:)) { return false }
    return super.canPerformAction(action, withSender: sender)
  }

  override func delete(_ sender: Any?) {
    guard selectedRange.length > 0, let onDeleteMessage else { return }
    resignFirstResponder()
    onDeleteMessage()
  }

  @objc func showPeerMessageActions(_ sender: Any?) {
    guard selectedRange.length > 0, let onMoreMessage else { return }
    resignFirstResponder()
    onMoreMessage()
  }
}

enum GalaxySSIPeerTextRenderer {
  static func transcript(_ text: String, fontSize: CGFloat, outgoing: Bool) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = outgoing ? .right : .natural
    return NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize),
      .foregroundColor: UIColor(Color.galaxySSITextSecondary), .paragraphStyle: paragraph])
  }

  static func render(_ blocks: [AgentRichBlock], fontSize: CGFloat) -> NSAttributedString {
    let output = NSMutableAttributedString(string: "")
    for block in blocks where AgentRichSelectableParagraphs.supports(block) {
      if output.length > 0 { output.append(NSAttributedString(string: "\n\n")) }
      let heading = block.type == .heading
      let size = heading ? fontSize * ((Int(block.metadata["level"] ?? "") ?? 2) == 1 ? 20 : 18) / 17 : fontSize
      let color = UIColor(block.type == .quote || block.type == .divider ? Color.galaxySSITextSecondary : .galaxySSITextPrimary)
      let value: String
      if block.type == .list {
        value = block.rows.map {
          "\(AgentRichSelectableParagraphs.listMarkerLabel($0.first ?? "")) \($0.dropFirst().joined(separator: " "))"
        }.joined(separator: "\n")
      } else if block.type == .divider {
        value = String(repeating: "\u{2500}", count: 8)
      } else { value = block.text.ifBlank(block.title) }
      for segment in AgentInlineMarkdown.parse(value) {
        var font = UIFont.systemFont(ofSize: size, weight: heading ? .bold : .regular)
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        switch segment.style {
        case .bold: font = .boldSystemFont(ofSize: size)
        case .italic:
          if let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            font = UIFont(descriptor: descriptor, size: size)
          }
        case .code: font = .monospacedSystemFont(ofSize: size, weight: .regular)
        case .strike: attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        case .link:
          if let url = URL(string: segment.url) { attributes[.link] = url }
          attributes[.foregroundColor] = UIColor(Color.galaxySSIAccent)
          attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        case .normal: break
        }
        attributes[.font] = font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        attributes[.paragraphStyle] = paragraph
        output.append(NSAttributedString(string: segment.text, attributes: attributes))
      }
    }
    return output
  }

  static func size(_ text: NSAttributedString, maximumWidth: CGFloat) -> CGSize {
    let width = maximumWidth.isFinite ? max(1, maximumWidth) : 240
    let storage = NSTextStorage(attributedString: text)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    layout.ensureLayout(for: container)
    let used = layout.usedRect(for: container)
    return CGSize(width: min(width, max(1, ceil(used.maxX) + 1)), height: max(1, ceil(used.height) + 1))
  }
}
