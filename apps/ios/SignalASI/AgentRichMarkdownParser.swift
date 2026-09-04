import Foundation

extension AgentRichContentCodec {
  static func fromText(_ text: String) -> [AgentRichBlock] {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    if let pretty = prettyJSON(clean) {
      return [AgentRichBlock(id: markdownID(), type: .json, text: pretty, language: "json")]
    }

    var blocks: [AgentRichBlock] = []
    var paragraph: [String] = []
    let lines = clean.components(separatedBy: .newlines)
    var index = 0

    func flushParagraph() {
      let value = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty {
        blocks.append(AgentRichBlock(id: markdownID(), type: .text, text: value))
      }
      paragraph.removeAll()
    }

    while index < lines.count && blocks.count < maximumBlocks {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("```") {
        flushParagraph()
        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        index += 1
        var code: [String] = []
        while index < lines.count {
          let candidate = lines[index]
          if candidate.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
            break
          }
          code.append(candidate)
          index += 1
        }
        let codeText = code.joined(separator: "\n")
        let richBlocks = language.caseInsensitiveCompare("signalasi-rich") == .orderedSame
          ? signalASIRichBlocks(codeText)
          : []
        if language.caseInsensitiveCompare("mermaid") == .orderedSame {
          blocks.append(
            AgentRichBlock(
              id: markdownID(),
              type: .mermaid,
              text: codeText,
              language: "mermaid"
            )
          )
        } else if !richBlocks.isEmpty {
          blocks.append(contentsOf: richBlocks)
        } else {
          blocks.append(
            AgentRichBlock(
              id: markdownID(),
              type: .code,
              text: codeText,
              language: language
            )
          )
        }
      } else if let firstItem = parseListItem(line) {
        flushParagraph()
        var rows: [[String]] = []
        var ordered = firstItem.ordered
        var checklist = firstItem.checklist
        var itemIndex = index
        while itemIndex < lines.count, let item = parseListItem(lines[itemIndex]) {
          rows.append([item.marker, item.text])
          ordered = ordered || item.ordered
          checklist = checklist || item.checklist
          itemIndex += 1
        }
        blocks.append(
          AgentRichBlock(
            id: markdownID(),
            type: .list,
            rows: rows,
            metadata: [
              "style": checklist ? "checklist" : (ordered ? "ordered" : "bullet")
            ]
          )
        )
        index = itemIndex
        continue
      } else if isTableHeader(lines, index) {
        flushParagraph()
        let columns = tableCells(lines[index])
        index += 2
        var rows: [[String]] = []
        while index < lines.count, lines[index].contains("|"), rows.count < 500 {
          rows.append(Array(tableCells(lines[index]).prefix(24)))
          index += 1
        }
        blocks.append(
          AgentRichBlock(id: markdownID(), type: .table, columns: columns, rows: rows)
        )
        continue
      } else if trimmed.range(of: #"^#{1,6}\s+.+"#, options: .regularExpression) != nil {
        flushParagraph()
        let level = trimmed.prefix { $0 == "#" }.count
        let heading = trimmed.dropFirst(level).trimmingCharacters(in: .whitespacesAndNewlines)
        blocks.append(
          AgentRichBlock(id: markdownID(), type: .heading, text: heading, metadata: ["level": String(level)])
        )
      } else if trimmed.hasPrefix("> ") {
        flushParagraph()
        var quote: [String] = []
        while index < lines.count {
          let candidate = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
          guard candidate.hasPrefix(">") else { break }
          var value = String(candidate.dropFirst())
          if value.first == " " { value.removeFirst() }
          quote.append(value)
          index += 1
        }
        blocks.append(AgentRichBlock(id: markdownID(), type: .quote, text: quote.joined(separator: "\n")))
        continue
      } else if isDivider(trimmed) {
        flushParagraph()
        blocks.append(AgentRichBlock(id: markdownID(), type: .divider))
      } else if trimmed.isEmpty {
        flushParagraph()
      } else {
        paragraph.append(line)
      }
      index += 1
    }
    flushParagraph()
    if let webpage = markdownWebPage(clean) {
      blocks.append(webpage)
    }
    return Array(blocks.prefix(maximumBlocks))
  }

  private static func signalASIRichBlocks(_ text: String) -> [AgentRichBlock] {
    guard let data = text.data(using: .utf8),
      let rawObject = try? JSONSerialization.jsonObject(with: data),
      let object = rawObject as? [String: Any] else {
      return []
    }
    var document: [String: Any]
    if object["blocks"] != nil {
      document = object
      document["version"] = document["version"] ?? version
    } else {
      document = ["version": version, "blocks": [object]]
    }
    guard let encoded = try? JSONSerialization.data(withJSONObject: document) else { return [] }
    return decode(String(decoding: encoded, as: UTF8.self))
  }

  private struct ParsedListItem {
    var marker: String
    var text: String
    var ordered: Bool
    var checklist: Bool
  }

  private static func parseListItem(_ line: String) -> ParsedListItem? {
    guard let groups = regexGroups(#"^\s*(?:(\d+)[.)]|([-+*]))\s+(.+)$"#, in: line),
      groups.count == 3 else { return nil }
    let rawText = groups[2].trimmingCharacters(in: .whitespacesAndNewlines)
    let check = regexGroups(#"^\[([ xX])]\s*(.*)$"#, in: rawText)
    let marker: String
    let itemText: String
    if let check, check.count == 2 {
      marker = check[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unchecked" : "checked"
      itemText = check[1].trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(rawText)
    } else {
      marker = groups[0].isEmpty ? "bullet" : groups[0]
      itemText = rawText
    }
    return ParsedListItem(
      marker: marker,
      text: itemText,
      ordered: !groups[0].isEmpty,
      checklist: check != nil
    )
  }

  private static func isTableHeader(_ lines: [String], _ index: Int) -> Bool {
    guard index + 1 < lines.count, lines[index].contains("|") else { return false }
    let separator = lines[index + 1]
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
    guard !separator.isEmpty else { return false }
    return separator.split(separator: "|").allSatisfy {
      regexMatches(#"^:?-{3,}:?$"#, value: String($0).trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private static func tableCells(_ line: String) -> [String] {
    line
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
      .split(separator: "|")
      .prefix(24)
      .map { String(String($0).trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000)) }
  }

  private static func isDivider(_ value: String) -> Bool {
    guard value.count >= 3, let first = value.first, "-*_".contains(first) else { return false }
    return value.allSatisfy { $0 == first }
  }

  private static func prettyJSON(_ value: String) -> String? {
    guard (value.hasPrefix("{") && value.hasSuffix("}")) || (value.hasPrefix("[") && value.hasSuffix("]")),
      let data = value.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      JSONSerialization.isValidJSONObject(object),
      let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
      return nil
    }
    return String(decoding: pretty, as: UTF8.self)
  }

  private static func markdownWebPage(_ text: String) -> AgentRichBlock? {
    guard let expression = try? NSRegularExpression(
      pattern: #"\[([^]]+)\]\((https://[^)\s]+)\)"#,
      options: [.caseInsensitive]
    ) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = expression.matches(in: text, range: range)
    guard matches.count == 1, let match = matches.first,
      let titleRange = Range(match.range(at: 1), in: text),
      let uriRange = Range(match.range(at: 2), in: text) else { return nil }
    let title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    let uri = String(text[uriRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    return AgentRichBlock(id: markdownID(), type: .webpage, title: title, uri: uri, fallbackText: uri)
  }

  private static func regexGroups(_ pattern: String, in value: String) -> [String]? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) else {
      return nil
    }
    return (1..<match.numberOfRanges).map { index in
      guard let range = Range(match.range(at: index), in: value) else { return "" }
      return String(value[range])
    }
  }

  private static func regexMatches(_ pattern: String, value: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }

  private static func markdownID() -> String {
    UUID().uuidString.lowercased()
  }
}
