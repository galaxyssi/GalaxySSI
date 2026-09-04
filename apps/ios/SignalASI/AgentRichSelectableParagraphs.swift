import SwiftUI

struct AgentRichBlockRun: Equatable {
  var blocks: [AgentRichBlock]
  var selectable: Bool
}

struct AgentRichSelectableParagraphs: View {
  var blocks: [AgentRichBlock]

  var body: some View {
    Text(Self.render(blocks))
      .font(.body)
      .foregroundColor(.signalASITextPrimary)
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
      content.foregroundColor = .signalASITextSecondary
    case .list:
      content = listContent(block.rows)
    case .divider:
      content = AttributedString(String(repeating: "\u{2500}", count: 8))
      content.foregroundColor = Color.signalASITextSecondary.opacity(0.55)
    default:
      content = AttributedString("")
    }
    return content
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
