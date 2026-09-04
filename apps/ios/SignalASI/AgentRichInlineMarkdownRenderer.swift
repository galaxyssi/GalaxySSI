import SwiftUI

enum AgentRichInlineMarkdownRenderer {
  static func render(_ value: String) -> AttributedString {
    var output = AttributedString("")
    for segment in AgentInlineMarkdown.parse(value) {
      var fragment = AttributedString(segment.text)
      switch segment.style {
      case .bold:
        fragment.inlinePresentationIntent = .stronglyEmphasized
      case .italic:
        fragment.inlinePresentationIntent = .emphasized
      case .strike:
        fragment.inlinePresentationIntent = .strikethrough
      case .code:
        fragment.inlinePresentationIntent = .code
      case .link:
        if let url = URL(string: segment.url) {
          fragment.link = url
        }
        fragment.foregroundColor = Color.signalASIAccent
        fragment.underlineStyle = .single
      case .normal:
        break
      }
      output.append(fragment)
    }
    return output
  }

  static func text(_ value: String) -> Text {
    Text(render(value)).font(.body)
  }
}
