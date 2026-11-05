import SwiftUI
import UIKit

struct AgentRichBlockRun: Equatable {
  var blocks: [AgentRichBlock]
  var selectable: Bool
}

struct AgentRichSelectableParagraphs: View {
  @Environment(\.agentReplyParagraphSpeechAction) private var paragraphSpeechAction
  @Environment(\.agentReplySpeechProse) private var speechProse
  @Environment(\.agentReplyNativeParagraphs) private var nativeParagraphs
  @Environment(\.agentReplySpeechBlankTap) private var blankTap
  @Environment(\.peerTextSelection) private var peerSelection

  var blocks: [AgentRichBlock]

  @ViewBuilder
  var body: some View {
    if let peerSelection, paragraphSpeechAction == nil {
      GalaxySSIPeerSelectableParagraphs(blocks: blocks, selection: peerSelection)
    } else if let paragraphSpeechAction {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
          if let selection = speechProse?.selection(for: block) {
            if nativeParagraphs {
              AgentReplySelectableParagraph(block: block, fallback: Self.render(block), blankTap: blankTap) { row in
                if let row {
                  if let selectedRow = speechProse?.selection(for: block, listRow: row) {
                    paragraphSpeechAction(selectedRow)
                  }
                } else {
                  paragraphSpeechAction(selection)
                }
              }
            } else {
              selectable(block).onTapGesture(count: 2) { paragraphSpeechAction(selection) }
            }
          } else if speechProse == nil, let selection = Self.selection(blocks: blocks, selectedIndex: index) {
            selectable(block).onTapGesture(count: 2) { paragraphSpeechAction(selection) }
          } else {
            selectable(block)
          }
        }
      }
    } else {
      Text(Self.render(blocks))
        .font(.body)
        .foregroundColor(.galaxySSITextPrimary)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
  }

  private func selectable(_ block: AgentRichBlock) -> some View {
    Text(Self.render(block))
      .font(.body)
      .foregroundColor(.galaxySSITextPrimary)
      .lineSpacing(4)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
  }

  static func supports(_ block: AgentRichBlock) -> Bool {
    supportedTypes.contains(block.type)
  }

  static func spacing(before block: AgentRichBlock) -> CGFloat {
    switch block.type {
    case .heading:
      return 12
    case .divider:
      return 10
    case .text, .list, .quote:
      return 6
    default:
      return 10
    }
  }

  static func runs(_ blocks: [AgentRichBlock]) -> [AgentRichBlockRun] {
    var result: [AgentRichBlockRun] = []
    var index = 0
    while index < blocks.count {
      let selectable = supports(blocks[index])
      var end = index + 1
      if selectable {
        while end < blocks.count, supports(blocks[end]) {
          end += 1
        }
      }
      result.append(
        AgentRichBlockRun(blocks: Array(blocks[index..<end]), selectable: selectable)
      )
      index = end
    }
    return result
  }

  static func render(_ blocks: [AgentRichBlock]) -> AttributedString {
    var output = AttributedString("")
    for block in blocks where supports(block) {
      if !output.characters.isEmpty {
        output.append(AttributedString("\n\n"))
      }
      output.append(render(block))
    }
    return output
  }

  private static func render(_ block: AgentRichBlock) -> AttributedString {
    var content: AttributedString
    switch block.type {
    case .text:
      content = AgentRichInlineMarkdownRenderer.render(block.text)
    case .heading:
      content = AgentRichInlineMarkdownRenderer.render(block.text.ifBlank(block.title))
      let level = Int(block.metadata["level"] ?? "") ?? 2
      content.font = .system(size: level == 1 ? 20 : 18, weight: .bold)
    case .quote:
      content = AgentRichInlineMarkdownRenderer.render(block.text)
      content.foregroundColor = .galaxySSITextSecondary
    case .list:
      content = listContent(block.rows)
    case .divider:
      content = AttributedString(String(repeating: "\u{2500}", count: 8))
      content.foregroundColor = Color.galaxySSITextSecondary.opacity(0.55)
    default:
      content = AttributedString("")
    }
    return content
  }

  private static func speechText(_ block: AgentRichBlock) -> String {
    AgentReplySpeechPresentationPolicy.paragraphText(block)
  }

  private static func selection(
    blocks: [AgentRichBlock],
    selectedIndex: Int
  ) -> AgentReplyParagraphSpeechSelection? {
    var sourceText = ""
    var selectedParagraph = ""
    var selectedOffset: Int?
    for (index, block) in blocks.enumerated() {
      let paragraph = speechText(block).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !paragraph.isEmpty else { continue }
      if !sourceText.isEmpty {
        sourceText += "\n\n"
      }
      if index == selectedIndex {
        selectedParagraph = paragraph
        selectedOffset = sourceText.count
      }
      sourceText += paragraph
    }
    guard let selectedOffset, !selectedParagraph.isEmpty else { return nil }
    return AgentReplyParagraphSpeechSelection(
      paragraph: selectedParagraph,
      sourceText: sourceText,
      startOffset: selectedOffset
    )
  }

  private static func listContent(_ rows: [[String]]) -> AttributedString {
    var output = AttributedString("")
    for (index, row) in rows.enumerated() {
      if index > 0 {
        output.append(AttributedString("\n"))
      }
      output.append(AttributedString("\(listMarkerLabel(row.first ?? "")) "))
      output.append(AgentRichInlineMarkdownRenderer.render(row.dropFirst().joined(separator: " ")))
    }
    return output
  }

  static func listMarkerLabel(_ marker: String) -> String {
    switch marker.lowercased() {
    case "checked": return "\u{2713}"
    case "unchecked": return "\u{25CB}"
    case "bullet": return "\u{2022}"
    default: return marker.hasSuffix(".") ? marker : "\(marker)."
    }
  }

  private static let supportedTypes: Set<AgentRichBlockType> = [
    .text,
    .heading,
    .quote,
    .list,
    .divider
  ]
}

private struct AgentReplySelectableParagraph: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
  @State private var width: CGFloat = 0
  let block: AgentRichBlock
  let fallback: AttributedString
  let blankTap: (() -> Void)?
  let speak: (Int?) -> Void

  var body: some View {
    Group {
      if width > 0 {
        let text = GalaxySSIPeerTextRenderer.render([block], fontSize: fontSize)
        AgentReplyParagraphText(text: text, actionTitle: GalaxySSILocalization.string(
          "galaxyssi.agent.reply_speech.paragraph", fallback: "Read from this paragraph", language: language),
          speak: { speak(listRow(at: $0)) }, blankTap: blankTap)
          .frame(width: width, height: GalaxySSIPeerTextRenderer.size(text, maximumWidth: width).height)
      } else {
        Text(fallback).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      }
    }
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    .background {
      GeometryReader { proxy in
        Color.clear
          .onAppear { width = proxy.size.width }
          .onChange(of: proxy.size.width) { width = $0 }
          .allowsHitTesting(false)
      }
    }
  }

  private func listRow(at location: Int?) -> Int? {
    guard block.type == .list, let location else { return nil }
    var offset = 0
    for (index, row) in block.rows.enumerated() {
      let marker = AgentRichSelectableParagraphs.listMarkerLabel(row.first ?? "")
      let rendered = AgentInlineMarkdown.parse("\(marker) \(row.dropFirst().joined(separator: " "))")
      offset += rendered.reduce(0) { $0 + $1.text.utf16.count }
      if location < offset { return index }
      offset += 1
    }
    return nil
  }
}

private struct AgentReplyParagraphText: UIViewRepresentable {
  let text: NSAttributedString
  let actionTitle: String
  let speak: (Int?) -> Void
  let blankTap: (() -> Void)?

  func makeUIView(context: Context) -> AgentReplyParagraphTextView {
    let view = AgentReplyParagraphTextView(frame: .zero, textContainer: nil)
    view.accessibilityIdentifier = "ios.agent.reply-speech.paragraph"
    return view
  }

  func updateUIView(_ view: AgentReplyParagraphTextView, context: Context) {
    if view.attributedText?.isEqual(to: text) != true { view.attributedText = text }
    view.speak = speak
    view.blankTap = blankTap
    view.accessibilityCustomActions = [UIAccessibilityCustomAction(name: actionTitle) { [weak view] _ in
      guard let speak = view?.speak else { return false }
      speak(nil)
      return true
    }]
  }
}

final class AgentReplyParagraphTextView: UITextView, UIGestureRecognizerDelegate {
  var speak: ((Int?) -> Void)?
  var blankTap: (() -> Void)?

  private lazy var paragraphTap: UITapGestureRecognizer = {
    let tap = UITapGestureRecognizer(target: self, action: #selector(readParagraph))
    tap.numberOfTapsRequired = 2
    tap.delegate = self
    return tap
  }()
  private lazy var emptyTap: UITapGestureRecognizer = {
    let tap = UITapGestureRecognizer(target: self, action: #selector(stopAtBlank))
    tap.delegate = self
    tap.cancelsTouchesInView = false
    return tap
  }()
  private lazy var emptyDoubleTap: UITapGestureRecognizer = {
    let tap = UITapGestureRecognizer(target: self, action: #selector(ignoreBlankDoubleTap))
    tap.numberOfTapsRequired = 2
    tap.delegate = self
    tap.cancelsTouchesInView = false
    return tap
  }()

  override init(frame: CGRect, textContainer: NSTextContainer?) {
    super.init(frame: frame, textContainer: textContainer)
    isEditable = false
    isSelectable = true
    isScrollEnabled = false
    backgroundColor = .clear
    textContainerInset = .zero
    textContainer.lineFragmentPadding = 0
    addGestureRecognizer(paragraphTap)
    addGestureRecognizer(emptyDoubleTap)
    addGestureRecognizer(emptyTap)
    emptyTap.require(toFail: emptyDoubleTap)
  }

  required init?(coder: NSCoder) { return nil }

  func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard selectedRange.length == 0 else { return false }
    switch hit(at: touch.location(in: self)) {
    case .text: return gesture === paragraphTap && speak != nil
    case .blank: return (gesture === emptyTap || gesture === emptyDoubleTap) && blankTap != nil
    case .link: return false
    }
  }

  func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    // Give the speech recognizer priority over native double-tap word selection, not long press or drags.
    guard gesture === paragraphTap, other.view === self, let tap = other as? UITapGestureRecognizer,
          other !== emptyDoubleTap else { return false }
    return tap.numberOfTapsRequired >= 2
  }

  @objc private func readParagraph() {
    guard selectedRange.length == 0, case .text(let index) = hit(at: paragraphTap.location(in: self)) else { return }
    speak?(index)
  }

  @objc private func stopAtBlank() {
    guard selectedRange.length == 0, hit(at: emptyTap.location(in: self)) == .blank else { return }
    blankTap?()
  }

  @objc private func ignoreBlankDoubleTap() {}

  enum Hit: Equatable { case blank, text(Int), link }

  func hit(at point: CGPoint) -> Hit {
    guard bounds.contains(point), let attributedText, attributedText.length > 0 else { return .blank }
    let point = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
    layoutManager.ensureLayout(for: textContainer)
    guard layoutManager.usedRect(for: textContainer).contains(point), layoutManager.numberOfGlyphs > 0 else {
      return .blank
    }
    let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
    guard glyph < layoutManager.numberOfGlyphs,
          layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(point)
    else { return .blank }
    let index = layoutManager.characterIndexForGlyph(at: glyph)
    guard index < attributedText.length,
          let range = Range((attributedText.string as NSString).rangeOfComposedCharacterSequence(at: index),
                            in: attributedText.string),
          !attributedText.string[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return .blank }
    return attributedText.attribute(.link, at: index, effectiveRange: nil) == nil ? .text(index) : .link
  }
}
