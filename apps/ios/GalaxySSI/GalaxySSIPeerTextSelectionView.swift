import SwiftUI
import UIKit

struct GalaxySSIPeerTextSelectionContext {
  var maximumWidth: CGFloat
  var onDelete: () -> Void
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
      onDelete: selection.onDelete)
      .frame(width: size.width, height: size.height, alignment: .leading)
  }
}

struct GalaxySSIPeerTextSelectionView: UIViewRepresentable {
  var text: NSAttributedString
  var deleteTitle: String
  var onDelete: () -> Void

  func makeUIView(context: Context) -> GalaxySSIPeerSelectionTextView {
    let view = GalaxySSIPeerSelectionTextView()
    view.isEditable = false
    view.isSelectable = true
    view.isScrollEnabled = false
    view.backgroundColor = .clear
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.delegate = context.coordinator
    view.accessibilityIdentifier = "ios.peer-message.selectable-text"
    return view
  }

  func updateUIView(_ view: GalaxySSIPeerSelectionTextView, context: Context) {
    if view.attributedText?.isEqual(to: text) != true {
      view.attributedText = text
      view.selectedRange = NSRange(location: 0, length: 0)
    }
    view.onDeleteMessage = onDelete
    view.deleteTitle = deleteTitle
  }

  static func dismantleUIView(_ view: GalaxySSIPeerSelectionTextView, coordinator: Coordinator) {
    view.onDeleteMessage = nil
    view.resignFirstResponder()
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, UITextViewDelegate {
    @available(iOS 16.0, *)
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                  suggestedActions: [UIMenuElement]) -> UIMenu? {
      guard let view = textView as? GalaxySSIPeerSelectionTextView,
            range.length > 0, view.onDeleteMessage != nil else { return nil }
      let delete = UIAction(title: view.deleteTitle, image: UIImage(systemName: "trash"),
        attributes: .destructive) { [weak view] _ in view?.delete(nil) }
      return UIMenu(children: suggestedActions + [delete])
    }
  }
}

final class GalaxySSIPeerSelectionTextView: UITextView {
  var onDeleteMessage: (() -> Void)?
  var deleteTitle = ""

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(UIResponderStandardEditActions.delete(_:)) {
      // Modern menus use the explicit destructive action; avoid a duplicate standard Delete.
      if #available(iOS 16.0, *) { return false }
      return onDeleteMessage != nil && selectedRange.length > 0
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
}

enum GalaxySSIPeerTextRenderer {
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
