import Foundation

enum GalaxySSIHealthMetric: String, Codable, CaseIterable, Identifiable {
  case bloodPressure
  case glucose
  case weight
  case heartRate
  case cholesterol
  case hemoglobin
  case restingHeartRate
  case sleepDuration
  case steps
  case temperature
  case oxygenSaturation
  case height
  case waist
  case bodyFat
  case ldl
  case hdl
  case triglycerides
  case hba1c
  case whiteBloodCells
  case platelets
  case alt
  case ast
  case creatinine
  case uricAcid
  case crp
  case tsh
  case urineProtein

  enum Group: String, CaseIterable {
    case cardiovascular, metabolic, sleep, activity, body, blood, liver, kidney, thyroid, urine

    func title(language: String) -> String {
      GalaxySSILocalization.string("galaxyssi.health.metric_group." + rawValue,
                                   fallback: rawValue.capitalized, language: language)
    }
  }

  enum Form: Equatable { case positive, nonnegative, count, laboratory, qualitative }
  struct Entry {
    let title: String
    let group: Group
    let units: [String]
    let form: Form
    let aliases: [String]

    init(_ title: String, _ group: Group, _ units: [String], _ form: Form, _ aliases: [String]) {
      self.title = title
      self.group = group
      self.units = units
      self.form = form
      self.aliases = aliases
    }
  }

  var id: String { rawValue }
  var unit: String { entry.units[0] }
  var units: [String] { entry.units }
  var form: Form { entry.form }
  var laboratory: Bool { form == .laboratory || form == .qualitative }

  var entry: Entry {
    switch self {
    case .bloodPressure: return .init("Blood pressure", .cardiovascular, ["mmHg", "kPa"], .positive, ["BP", "systolic", "diastolic"])
    case .glucose: return .init("Blood glucose", .metabolic, ["mmol/L", "mg/dL"], .laboratory, ["GLU", "FPG", "fasting glucose"])
    case .weight: return .init("Weight", .body, ["kg", "lb"], .positive, ["body weight"])
    case .heartRate: return .init("Heart rate", .cardiovascular, ["bpm"], .positive, ["HR", "pulse"])
    case .cholesterol: return .init("Total cholesterol", .metabolic, ["mmol/L", "mg/dL"], .laboratory, ["TC", "CHOL"])
    case .hemoglobin: return .init("Hemoglobin", .blood, ["g/L", "g/dL"], .laboratory, ["HGB", "Hb"])
    case .restingHeartRate: return .init("Resting heart rate", .cardiovascular, ["bpm"], .positive, ["RHR", "resting pulse"])
    case .sleepDuration: return .init("Sleep duration", .sleep, ["h", "min"], .nonnegative, ["sleep"])
    case .steps: return .init("Step count", .activity, ["steps"], .count, ["steps"])
    case .temperature: return .init("Body temperature", .body, ["\u{00B0}C", "\u{00B0}F"], .positive, ["temperature", "temp"])
    case .oxygenSaturation: return .init("Oxygen saturation", .cardiovascular, ["%"], .positive, ["SpO2"])
    case .height: return .init("Height", .body, ["cm", "m", "in"], .positive, [])
    case .waist: return .init("Waist circumference", .body, ["cm", "in"], .positive, ["waist"])
    case .bodyFat: return .init("Body fat percentage", .body, ["%"], .positive, ["body fat"])
    case .ldl: return .init("LDL cholesterol", .metabolic, ["mmol/L", "mg/dL"], .laboratory, ["LDL-C", "LDLC"])
    case .hdl: return .init("HDL cholesterol", .metabolic, ["mmol/L", "mg/dL"], .laboratory, ["HDL-C", "HDLC"])
    case .triglycerides: return .init("Triglycerides", .metabolic, ["mmol/L", "mg/dL"], .laboratory, ["TG", "TRIG"])
    case .hba1c: return .init("Glycated hemoglobin", .metabolic, ["%", "mmol/mol"], .laboratory, ["HbA1c", "A1C"])
    case .whiteBloodCells: return .init("White blood cells", .blood, ["10^9/L", "10^3/uL"], .laboratory, ["WBC", "leukocytes"])
    case .platelets: return .init("Platelet count", .blood, ["10^9/L", "10^3/uL"], .laboratory, ["PLT", "platelets"])
    case .alt: return .init("Alanine aminotransferase", .liver, ["U/L"], .laboratory, ["ALT", "GPT"])
    case .ast: return .init("Aspartate aminotransferase", .liver, ["U/L"], .laboratory, ["AST", "GOT"])
    case .creatinine: return .init("Creatinine", .kidney, ["umol/L", "mg/dL"], .laboratory, ["CREA", "Cr"])
    case .uricAcid: return .init("Uric acid", .kidney, ["umol/L", "mg/dL"], .laboratory, ["UA", "urate"])
    case .crp: return .init("C-reactive protein", .blood, ["mg/L", "mg/dL"], .laboratory, ["CRP", "hs-CRP"])
    case .tsh: return .init("Thyroid stimulating hormone", .thyroid, ["mIU/L", "uIU/mL"], .laboratory, ["TSH", "thyrotropin"])
    case .urineProtein: return .init("Urine protein screen", .urine, [""], .qualitative, ["PRO", "urine protein"])
    }
  }

  func title(language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.metric." + rawValue, fallback: entry.title, language: language)
  }

  func matches(_ query: String) -> Bool {
    func normalize(_ input: String) -> String {
      input.precomposedStringWithCompatibilityMapping.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "%" }
    }
    let aliases = GalaxySSILocalization.string("galaxyssi.health.metric_alias." + rawValue, fallback: "", language: "zh-CN")
    let tokens = ([entry.title, title(language: "zh-CN"), rawValue] + entry.aliases + units +
      aliases.split(separator: "|").map(String.init)).map(normalize)
    return query.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }.filter { !$0.isEmpty }
      .allSatisfy { term in tokens.contains { $0.contains(term) } }
  }
}

struct GalaxySSIHealthReportedResult: Codable, Equatable {
  enum Kind: String, Codable { case comparison, range, qualitative }
  let kind: Kind
  let raw: String
  let canonical: String
  var lower: Decimal?
  var upper: Decimal?
  var comparator: String?

  static func parse(_ input: String, metric: GalaxySSIHealthMetric, allowFreeformQualitative: Bool = true) -> Self? {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard metric.laboratory, !raw.isEmpty, raw.utf8.count <= 128,
          !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    let grade = raw.range(of: #"^(?:[1-4]\+|\+{1,4}|[+\-\u00B1])$"#, options: .regularExpression) != nil
    let normalized = raw.lowercased()
    let allowed = ["negative", "positive", "trace", "indeterminate", "inconclusive", "reactive",
                   "nonreactive", "non-reactive", "detected", "not detected",
                   "\u{9634}\u{6027}", "\u{9633}\u{6027}", "\u{5F31}\u{9633}\u{6027}", "\u{53EF}\u{7591}",
                   "\u{672A}\u{68C0}\u{51FA}", "\u{68C0}\u{51FA}"]
    if grade || allowed.contains(normalized) ||
        (allowFreeformQualitative && metric.form == .qualitative && raw.contains(where: \.isLetter) &&
          !raw.hasPrefix("=") && !raw.contains("<") && !raw.contains(">")) {
      return Self(kind: .qualitative, raw: raw, canonical: "label:" + normalized)
    }
    guard metric.form == .laboratory else { return nil }
    for (prefix, op) in [("<=", "<="), (">=", ">="), ("\u{2264}", "<="), ("\u{2265}", ">="),
                         ("\u{FF1C}", "<"), ("\u{FF1E}", ">"), ("<", "<"), (">", ">")]
      where raw.hasPrefix(prefix) {
      guard let value = number(String(raw.dropFirst(prefix.count))) else { return nil }
      return Self(kind: .comparison, raw: raw, canonical: op + exact(value), lower: value, comparator: op)
    }
    let range = raw.replacingOccurrences(of: " to ", with: "-", options: .caseInsensitive)
      .replacingOccurrences(of: "\u{2013}", with: "-").replacingOccurrences(of: "\u{2014}", with: "-")
      .replacingOccurrences(of: "~", with: "-").replacingOccurrences(of: "\u{301C}", with: "-")
      .replacingOccurrences(of: "\u{FF5E}", with: "-").replacingOccurrences(of: "\u{81F3}", with: "-")
    let parts = range.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, let low = number(String(parts[0])), let high = number(String(parts[1])), low <= high
    else { return nil }
    return Self(kind: .range, raw: raw, canonical: exact(low) + ".." + exact(high), lower: low, upper: high)
  }

  static func number(_ raw: String) -> Decimal? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.utf8.count <= 38,
          text.range(of: #"^(?:[0-9]+(?:[.,][0-9]+)?|[.,][0-9]+)$"#, options: .regularExpression) != nil
    else { return nil }
    return Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func exact(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}
