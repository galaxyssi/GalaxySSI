import Foundation

struct GalaxySSIHealthOCRLabRow: Equatable {
  let metric: GalaxySSIHealthMetric
  let notation: String
  let unit: String?
  let reference: String?

  private static let ambiguous: Set<String> = ["cr", "ua", "pro", "chol", "gpt", "got", "hb"]
  private static let labels: [String: GalaxySSIHealthMetric] = {
    var labels: [String: GalaxySSIHealthMetric] = ["glucose": .glucose, "hemoglobin a1c": .hba1c]
    for metric in GalaxySSIHealthMetric.allCases where metric.laboratory {
      let chineseAliases = GalaxySSILocalization.string("galaxyssi.health.metric_alias." + metric.rawValue,
                                                        fallback: "", language: "zh-CN")
      for label in [metric.entry.title, metric.title(language: "zh-CN")] + metric.entry.aliases +
        chineseAliases.split(separator: "|").map(String.init) {
        let key = normalized(label)
        if !key.isEmpty, !ambiguous.contains(key) { labels[key] = metric }
      }
    }
    return labels
  }()
  private static let labeled: NSRegularExpression = {
    let alternatives = labels.keys.sorted { ($0.count, $0) > ($1.count, $1) }.map { label in
      label.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
    }.joined(separator: "|")
    return try! NSRegularExpression(pattern: #"^(?:[0-9]{1,3}[.)]\s+)?("# + alternatives +
      #")(?=\s|[:=\uFF1A(\uFF08<>\u2264\u2265\uFF1C\uFF1E]|(?<=[\u3400-\u9FFF])[0-9])\s*[:=\uFF1A]?\s*(.+)$"#,
      options: .caseInsensitive)
  }()
  private static let referenceSuffix = try! NSRegularExpression(
    pattern: #"\s*[;\uFF1B]\s*(?:reference(?:\s+(?:range|interval))?|\u53C2\u8003(?:\u8303\u56F4|\u503C))\s*[:\uFF1A]\s*(.+)$"#,
    options: .caseInsensitive)
  private static let alternate = try! NSRegularExpression(pattern: #"^(.+?)\s*[(\uFF08]\s*(.+?)\s*[)\uFF09]$"#)
  private static let flag = try! NSRegularExpression(pattern: #"(?:\s+[HL]|\s*[\u2191\u2193])$"#)
  private static let units: [String: [NSRegularExpression]] = [
    "mmol/L": #"mmol\s*/\s*l"#, "mg/dL": #"mg\s*/\s*dl"#, "g/L": #"g\s*/\s*l"#, "g/dL": #"g\s*/\s*dl"#,
    "%": #"[%\uFF05]"#, "mmol/mol": #"mmol\s*/\s*mol"#,
    "10^9/L": #"(?:[x\u00D7]\s*)?10(?:\^\s*9|\u2079)\s*/\s*l"#,
    "10^3/uL": #"(?:[x\u00D7]\s*)?10(?:\^\s*3|\u00B3)\s*/\s*[u\u00B5\u03BC]l"#,
    "U/L": #"u\s*/\s*l"#, "umol/L": #"[u\u00B5\u03BC]mol\s*/\s*l"#, "mg/L": #"mg\s*/\s*l"#,
    "mIU/L": #"miu\s*/\s*l"#, "uIU/mL": #"[u\u00B5\u03BC]iu\s*/\s*ml"#
  ].mapValues { unit in
    [#"^(.+?)\s*(?:"# + unit + #")$"#,
     #"^(?:[(\uFF08]\s*(?:"# + unit + #")\s*[)\uFF09]|(?:"# + unit + #"))\s*[:=\uFF1A]?\s*(.+)$"#]
      .map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }
  }

  static func parse(_ input: String) -> Self? {
    let line = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard line.utf8.count <= 2_048, line.count <= 480, !line.contains(where: \.isNewline),
          !line.unicodeScalars.contains(where: { $0.value != 9 && CharacterSet.controlCharacters.contains($0) }),
          let label = capture(labeled, 1, in: line), let metric = labels[normalized(label)],
          let body = capture(labeled, 2, in: line) else { return nil }
    var value = body
    var reference: String?
    if let suffix = referenceSuffix.firstMatch(in: body, range: span(body)),
       let suffixRange = Range(suffix.range, in: body), let content = Range(suffix.range(at: 1), in: body) {
      let text = String(body[content]).trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty, text.count <= 200, text.utf8.count <= 512,
            !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
      reference = text
      value = String(body[..<suffixRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
    let flagged = flag.firstMatch(in: value, range: span(value)).flatMap { Range($0.range, in: value) }
    let parsed = row(metric, value) ?? flagged.flatMap { row(metric, String(value[..<$0.lowerBound])) }
    return parsed.map { .init(metric: metric, notation: $0.raw, unit: $0.unit, reference: reference) }
  }

  private typealias Result = (raw: String, unit: String?, kind: GalaxySSIHealthReportedResult.Kind?)

  private static func row(_ metric: GalaxySSIHealthMetric, _ text: String) -> Result? {
    if let direct = value(metric, text) { return direct }
    guard let primary = capture(alternate, 1, in: text).flatMap({ value(metric, $0) }),
          let other = capture(alternate, 2, in: text).flatMap({ value(metric, $0) }),
          let firstUnit = primary.unit, let otherUnit = other.unit,
          !firstUnit.isEmpty, !otherUnit.isEmpty, firstUnit != otherUnit, primary.kind == other.kind else { return nil }
    return (primary.raw, nil, primary.kind)
  }

  private static func value(_ metric: GalaxySSIHealthMetric, _ text: String) -> Result? {
    func parse(_ candidate: String, unit: String?) -> Result? {
      let raw = candidate.trimmingCharacters(in: .whitespaces)
      if metric.form != .qualitative, GalaxySSIHealthReportedResult.number(raw) != nil { return (raw, unit, nil) }
      guard let typed = GalaxySSIHealthReportedResult.parse(raw, metric: metric, allowFreeformQualitative: false),
            (typed.kind == .qualitative) == (metric.form == .qualitative) else { return nil }
      return (raw, metric.form == .qualitative ? "" : unit, typed.kind)
    }
    if let raw = parse(text, unit: nil) { return raw }
    for unit in metric.units {
      for pattern in units[unit] ?? [] {
        if let matched = capture(pattern, 1, in: text), let result = parse(matched, unit: unit) { return result }
      }
    }
    return nil
  }

  private static func normalized(_ text: String) -> String {
    text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func span(_ text: String) -> NSRange { NSRange(text.startIndex..<text.endIndex, in: text) }

  private static func capture(_ regex: NSRegularExpression, _ group: Int, in text: String) -> String? {
    guard let match = regex.firstMatch(in: text, range: span(text)),
          let range = Range(match.range(at: group), in: text) else { return nil }
    return String(text[range])
  }
}
