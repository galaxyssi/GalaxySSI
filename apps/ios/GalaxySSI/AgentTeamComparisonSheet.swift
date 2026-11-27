import Foundation

enum AgentTeamComparisonSheet {
  struct Sheet {
    let evidence: AgentMcpJSONObject
    let plannerObjective: String
    let table: String
    let winners: [String]
  }
  private static let decimal = #"-?(?:0|[1-9]\d{0,8})(?:\.\d{1,9})?"#
  private static func cells(_ raw: String) -> [String]? {
    let line = raw.trimmingCharacters(in: .whitespaces)
    guard line.hasPrefix("|"), line.hasSuffix("|"), line.count >= 2 else { return nil }
    return String(line.dropFirst().dropLast()).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
  }
  private static func exact(_ value: String, _ pattern: String) -> Bool {
    value.range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil
  }
  static func evaluate(_ objective: String) -> Sheet? {
    guard objective.utf16.count <= 8_000 else { return nil }
    let lines = objective.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    let localized = ["input", "gate"].map { key in
      GalaxySSILocalization.string("galaxyssi.conversation_team.table_" + key, fallback: key, language: LanguagePolicySettings.zhCN)
    }
    let headers = lines.indices.filter { index in
      guard let fields = cells(lines[index]) else { return false }
      let first = Array(fields.prefix(2)).map { $0.lowercased() }
      return first == ["input", "gate"] || first == localized
    }
    guard headers.count == 1, let start = headers.first, let header = cells(lines[start]),
      lines.indices.contains(start + 1), let dividers = cells(lines[start + 1]), dividers.count == header.count,
      dividers.allSatisfy({ exact($0, #":?-{3,}:?"#) }) else { return nil }
    let names = Array(header.dropFirst(2))
    guard (1...10).contains(names.count), Set(names).count == names.count,
      names.allSatisfy({ !$0.isBlank && $0.utf16.count <= 40 }),
      let gatePattern = try? NSRegularExpression(pattern: "^(<=|>=|<|>)\\s*(" + decimal + ")$") else { return nil }
    var end = start + 2
    while end < lines.count && lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("|") { end += 1 }
    guard (1...32).contains(end - start - 2) else { return nil }
    var seen = Set<String>(), passes = Set(names), rows: [AgentMcpJSONValue] = [], points: [String] = []
    var gates = 0
    for line in lines[(start + 2)..<end] {
      guard let fields = cells(line), fields.count == header.count, !fields[0].isBlank,
        fields[0].utf16.count <= 40, seen.insert(fields[0]).inserted else { return nil }
      let gate = gatePattern.firstMatch(in: fields[1], range: NSRange(fields[1].startIndex..., in: fields[1]))
      guard gate != nil || fields[1] == "-" else { return nil }
      let operation: String?, threshold: Decimal?
      if let gate, let op = Range(gate.range(at: 1), in: fields[1]), let bound = Range(gate.range(at: 2), in: fields[1]) {
        operation = String(fields[1][op]); threshold = Decimal(string: String(fields[1][bound]), locale: Locale(identifier: "en_US_POSIX"))
        guard threshold != nil else { return nil }; gates += 1
      } else { operation = nil; threshold = nil }
      var series: AgentMcpJSONObject = [:]
      for (index, name) in names.enumerated() {
        let raw = fields[index + 2]
        guard exact(raw, decimal), let number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var value: AgentMcpJSONObject = ["value": .string(raw)]
        if let operation, let threshold {
          // Compare printed decimals exactly; never round through binary floating point.
          let order = NSDecimalNumber(decimal: number).compare(NSDecimalNumber(decimal: threshold))
          let pass: Bool
          switch operation {
          case "<": pass = order == .orderedAscending
          case "<=": pass = order != .orderedDescending
          case ">": pass = order == .orderedDescending
          default: pass = order != .orderedAscending
          }
          value["pass"] = .bool(pass)
          if !pass { passes.remove(name) }
        }
        series[name] = .object(value)
      }
      rows.append(.object(["input": .string(fields[0]), "gate": .string(fields[1]), "series": .object(series)]))
      points.append("x=" + fields[0] + ": " + names.enumerated().map { "\($0.element)=\(fields[$0.offset + 2])" }.joined(separator: ", "))
    }
    guard gates > 0 else { return nil }
    let winners = names.filter(passes.contains)
    let before = lines[..<start].joined(separator: "\n").trimmingCharacters(in: .newlines)
    let after = lines[end...].joined(separator: "\n")
    let planner = (before + " " + points.joined(separator: "; ") + "\n" + after).trimmingCharacters(in: .whitespacesAndNewlines)
    return Sheet(evidence: ["rows": .array(rows), "pass_all": .array(winners.map(AgentMcpJSONValue.string))],
      plannerObjective: planner, table: lines[start..<end].joined(separator: "\n"), winners: winners)
  }
}
