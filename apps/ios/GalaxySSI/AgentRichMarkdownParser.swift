import Foundation

enum AgentMarkdownArtifactReferences {
  static func removingInternalLinks(_ text: String) -> String {
    guard text.range(of: "galaxyssi-artifact://", options: .caseInsensitive) != nil else { return text }
    let characters = Array(text)
    var output = ""
    var index = 0
    var fence: (character: Character, count: Int)?
    while index < characters.count {
      let lineStart = index == 0 || characters[index - 1] == "\n"
      if lineStart, let marker = fenceMarker(characters, at: index) {
        if let fence, marker.character == fence.character, marker.count >= fence.count {
          self.appendLine(from: index, characters: characters, to: &output, next: &index)
          fence = nil
          continue
        }
        if fence == nil {
          fence = marker
          self.appendLine(from: index, characters: characters, to: &output, next: &index)
          continue
        }
      }
      if fence != nil {
        output.append(characters[index])
        index += 1
        continue
      }
      if characters[index] == "`", let end = inlineCodeEnd(characters, at: index) {
        output.append(contentsOf: characters[index..<end])
        index = end
        continue
      }
      if characters[index] == "\\", index + 1 < characters.count {
        output.append(characters[index])
        output.append(characters[index + 1])
        index += 2
        continue
      }
      if let link = markdownLink(characters, at: index),
         link.destination.lowercased().hasPrefix("galaxyssi-artifact://") {
        index = link.end
        continue
      }
      output.append(characters[index])
      index += 1
    }
    return output
  }

  private static func fenceMarker(_ value: [Character], at lineStart: Int) -> (Character, Int)? {
    var index = lineStart
    var spaces = 0
    while index < value.count, value[index] == " ", spaces < 4 {
      spaces += 1
      index += 1
    }
    guard spaces <= 3, index < value.count, value[index] == "`" || value[index] == "~" else { return nil }
    let character = value[index]
    var end = index
    while end < value.count, value[end] == character { end += 1 }
    let count = end - index
    return count >= 3 ? (character, count) : nil
  }

  private static func appendLine(
    from start: Int,
    characters: [Character],
    to output: inout String,
    next: inout Int
  ) {
    var end = start
    while end < characters.count {
      let character = characters[end]
      end += 1
      if character == "\n" { break }
    }
    output.append(contentsOf: characters[start..<end])
    next = end
  }

  private static func inlineCodeEnd(_ value: [Character], at start: Int) -> Int? {
    var openingEnd = start
    while openingEnd < value.count, value[openingEnd] == "`" { openingEnd += 1 }
    let count = openingEnd - start
    var index = openingEnd
    while index < value.count {
      guard value[index] == "`" else {
        index += 1
        continue
      }
      var end = index
      while end < value.count, value[end] == "`" { end += 1 }
      if end - index == count { return end }
      index = end
    }
    return nil
  }

  private static func markdownLink(
    _ value: [Character],
    at start: Int
  ) -> (destination: String, end: Int)? {
    var labelStart = start
    if value[start] == "!" {
      guard start + 1 < value.count, value[start + 1] == "[" else { return nil }
      labelStart += 1
    } else if value[start] != "[" {
      return nil
    }
    var labelEnd = labelStart + 1
    while labelEnd < value.count {
      if value[labelEnd] == "\\" { labelEnd += 2; continue }
      if value[labelEnd] == "]" { break }
      labelEnd += 1
    }
    guard labelEnd < value.count else { return nil }
    var index = labelEnd + 1
    while index < value.count, value[index].isWhitespace { index += 1 }
    guard index < value.count, value[index] == "(" else { return nil }
    index += 1
    while index < value.count, value[index].isWhitespace { index += 1 }
    let destination: String
    if index < value.count, value[index] == "<" {
      index += 1
      let destinationStart = index
      while index < value.count, value[index] != ">" { index += 1 }
      guard index < value.count else { return nil }
      destination = String(value[destinationStart..<index])
      index += 1
    } else {
      let destinationStart = index
      var depth = 0
      while index < value.count {
        if value[index] == "\\" {
          guard index + 1 < value.count else { return nil }
          index += 2
          continue
        }
        if value[index] == "(" { depth += 1 }
        if value[index] == ")" {
          if depth == 0 { break }
          depth -= 1
        }
        if value[index].isWhitespace, depth == 0 { break }
        index += 1
      }
      destination = String(value[destinationStart..<index])
    }
    var quote: Character?
    while index < value.count {
      let character = value[index]
      if character == "\\" {
        guard index + 1 < value.count else { return nil }
        index += 2
        continue
      }
      if let activeQuote = quote {
        if character == activeQuote { quote = nil }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character == ")" {
        return (destination, index + 1)
      }
      index += 1
    }
    return nil
  }
}

extension AgentRichContentCodec {
  static func fromText(_ text: String) -> [AgentRichBlock] {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    if let pretty = prettyJSON(clean) {
      return [AgentRichBlock(id: markdownID(), type: .json, text: pretty, language: "json")]
    }
    let visible = AgentMarkdownArtifactReferences.removingInternalLinks(clean)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !visible.isEmpty else { return [] }

    var blocks: [AgentRichBlock] = []
    var paragraph: [String] = []
    let lines = visible.components(separatedBy: .newlines)
    var index = 0

    func flushParagraph() {
      let value = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty {
        blocks.append(contentsOf: markdownImageBlocks(value))
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
        let richBlocks = language.caseInsensitiveCompare("galaxyssi-rich") == .orderedSame
          ? galaxySSIRichBlocks(codeText)
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
    return Array(blocks.prefix(maximumBlocks))
  }

  private static func galaxySSIRichBlocks(_ text: String) -> [AgentRichBlock] {
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

  private static func markdownImageBlocks(_ text: String) -> [AgentRichBlock] {
    var result: [AgentRichBlock] = []
    var cursor = text.startIndex
    var search = cursor
    var promoted = 0
    while promoted < 32,
          let marker = text.range(of: "![", range: search..<text.endIndex) {
      if marker.lowerBound > text.startIndex,
         text[text.index(before: marker.lowerBound)] == "\\" {
        search = marker.upperBound
        continue
      }
      let prefix = text[cursor..<marker.lowerBound]
      if prefix.filter({ $0 == "`" }).count % 2 == 1 {
        search = marker.upperBound
        continue
      }
      guard let altEnd = text[marker.upperBound...].firstIndex(of: "]"),
            text.index(after: altEnd) < text.endIndex,
            text[text.index(after: altEnd)] == "(" else { break }
      let bodyStart = text.index(altEnd, offsetBy: 2)
      var index = bodyStart
      var depth = 0
      var destinationEnd: String.Index?
      let angled = index < text.endIndex && text[index] == "<"
      if angled { index = text.index(after: index) }
      let destinationStart = index
      while index < text.endIndex {
        let character = text[index]
        if angled, character == ">" {
          destinationEnd = index
          index = text.index(after: index)
          break
        }
        if !angled {
          if character == "(" { depth += 1 }
          if character == ")" {
            if depth == 0 { destinationEnd = index; break }
            depth -= 1
          }
          if character.isWhitespace && depth == 0 { destinationEnd = index; break }
        }
        index = text.index(after: index)
      }
      guard let destinationEnd else { break }
      while index < text.endIndex, text[index] != ")" { index = text.index(after: index) }
      guard index < text.endIndex else { break }
      let destination = String(text[destinationStart..<destinationEnd])
        .replacingOccurrences(of: "&amp;", with: "&")
      guard isSafeMarkdownImageURL(destination) else {
        search = text.index(after: index)
        continue
      }
      let imageEnd = text.index(after: index)
      var promotedStart = marker.lowerBound
      var promotedEnd = imageEnd
      var sourceURL: String?
      if marker.lowerBound > text.startIndex {
        let opening = text.index(before: marker.lowerBound)
        if text[opening] == "[", imageEnd < text.endIndex, text[imageEnd] == "]" {
          let sourceOpen = text.index(after: imageEnd)
          if sourceOpen < text.endIndex, text[sourceOpen] == "(" {
            let sourceStart = text.index(after: sourceOpen)
            var sourceCursor = sourceStart
            let sourceAngled = sourceCursor < text.endIndex && text[sourceCursor] == "<"
            if sourceAngled { sourceCursor = text.index(after: sourceCursor) }
            let valueStart = sourceCursor
            while sourceCursor < text.endIndex,
                  text[sourceCursor] != (sourceAngled ? ">" : ")") {
              sourceCursor = text.index(after: sourceCursor)
            }
            let value = String(text[valueStart..<sourceCursor]).replacingOccurrences(of: "&amp;", with: "&")
            if sourceCursor < text.endIndex, sourceAngled {
              sourceCursor = text.index(after: sourceCursor)
            }
            if sourceCursor < text.endIndex, text[sourceCursor] == ")", isSafeMarkdownImageURL(value) {
              promotedStart = opening
              promotedEnd = text.index(after: sourceCursor)
              sourceURL = value
            }
          }
        }
      }
      let leading = String(text[cursor..<promotedStart]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !leading.isEmpty { result.append(AgentRichBlock(id: markdownID(), type: .text, text: leading)) }
      let alt = String(text[marker.upperBound..<altEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
      result.append(AgentRichBlock(
        id: markdownID(),
        type: .image,
        title: String(alt.prefix(500)),
        uri: destination,
        metadata: ["markdown_image_source": destination]
      ))
      if let sourceURL {
        let label = alt.ifBlank("Source")
          .replacingOccurrences(of: "\\", with: "\\\\")
          .replacingOccurrences(of: "[", with: "\\[")
          .replacingOccurrences(of: "]", with: "\\]")
          .replacingOccurrences(of: "\n", with: " ")
          .replacingOccurrences(of: "\r", with: " ")
        result.append(AgentRichBlock(
          id: markdownID(),
          type: .text,
          text: "[\(label)](<\(sourceURL)>)"
        ))
      }
      promoted += 1
      cursor = promotedEnd
      search = cursor
    }
    let trailing = String(text[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
    if !trailing.isEmpty { result.append(AgentRichBlock(id: markdownID(), type: .text, text: trailing)) }
    return result.isEmpty ? [AgentRichBlock(id: markdownID(), type: .text, text: text)] : result
  }

  private static func isSafeMarkdownImageURL(_ value: String) -> Bool {
    guard value.utf8.count <= 4_096,
          let components = URLComponents(string: value),
          ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
          !(components.host ?? "").isEmpty,
          components.user == nil,
          components.password == nil else { return false }
    return true
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
