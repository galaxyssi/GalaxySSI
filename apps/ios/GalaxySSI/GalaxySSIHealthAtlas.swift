import Foundation

/// Public teaching content only: this graph never loads the health archive.
struct GalaxySSIHealthAtlas: Decodable {
  enum Kind: String, Decodable { case system, organ, cell, fragment }
  struct Entry: Decodable, Identifiable {
    let id: String
    let kind: Kind
    let name: String
    let description: String
    let systems: [String]
    let related: [String]
    let mechanism: String
    let aliases: String
    let color: String
    let icon: String
  }
  struct Mechanism: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let stages: [String]
    let chapter: String
    var source: URL { URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/" + chapter)! }
  }
  let schema: Int
  let entries: [Entry]
  let mechanisms: [Mechanism]
  enum Invalid: Error { case catalogue }

  static func load(bundle: Bundle = .main) throws -> Self {
    guard let url = bundle.url(forResource: "body-atlas", withExtension: "json", subdirectory: "body-atlas")
    else { throw Invalid.catalogue }
    return try validated(JSONDecoder().decode(Self.self, from: Data(contentsOf: url)))
  }

  static func validated(_ atlas: Self) throws -> Self {
    let ids = Set(atlas.entries.map(\.id)), models = Set(atlas.mechanisms.map(\.id))
    guard atlas.schema == 1, ids.count == atlas.entries.count, models.count == atlas.mechanisms.count,
      !ids.isEmpty, !models.isEmpty,
      atlas.entries.allSatisfy({ entry in
        entry.id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil &&
        !entry.name.isEmpty && !entry.description.isEmpty && !entry.systems.isEmpty &&
        entry.systems.allSatisfy({ atlas.entry($0)?.kind == .system }) &&
        entry.related.allSatisfy(ids.contains) && !entry.related.contains(entry.id) && models.contains(entry.mechanism)
      }), atlas.mechanisms.allSatisfy({ model in
        model.stages.count == 4 && model.stages.allSatisfy({ !$0.isEmpty }) &&
        model.chapter.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
      }) else { throw Invalid.catalogue }
    return atlas
  }

  func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }
  func model(_ entry: Entry) -> Mechanism { mechanisms.first { $0.id == entry.mechanism }! }
  func children(_ entry: Entry) -> [Entry] { entry.related.compactMap(self.entry) }
  func parents(_ entry: Entry) -> [Entry] { entries.filter { $0.kind != .system && $0.related.contains(entry.id) } }
  func cells(_ entry: Entry) -> [Entry] {
    entries.filter { ($0.kind == .cell || $0.kind == .fragment) &&
      (entry.kind == .system ? $0.systems.contains(entry.id) : $0.related.contains(entry.id)) }
  }
  func search(_ query: String, kind: Kind?, system: String, language: String) -> [Entry] {
    let words = query.lowercased().split(whereSeparator: \.isWhitespace)
    return entries.filter { entry in
      guard kind == nil || entry.kind == kind || (kind == .cell && entry.kind == .fragment),
        system.isEmpty || entry.systems.contains(system) else { return false }
      let haystack = [entry.name, entry.description, entry.aliases].map { GalaxySSIHealthAtlasText.get($0, language) }
        .joined(separator: " ").lowercased() + " " + entry.id
      return words.allSatisfy { haystack.contains($0) }
    }
  }
}

enum GalaxySSIHealthAtlasText {
  static func get(_ key: String, _ language: String) -> String {
    let name = LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en"
    let english = localized(key, locale: "en", fallback: key)
    return localized(key, locale: name, fallback: english)
  }
  private static func localized(_ key: String, locale: String, fallback: String) -> String {
    guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
    return bundle.localizedString(forKey: key, value: fallback, table: "BodyAtlas")
  }
}

struct GalaxySSIHealthAtlasSimulation: Equatable, Codable {
  var first: Double = 70
  var second: Double = 70
  var phase: Double = 0
  var speed: Double = 1
  var stage: Int { min(3, max(0, Int(phase * 4))) }
  var output: Double { first * second / 1000 }
  static func initial(_ id: String) -> Self {
    ["lungs", "respiratory"].contains(id) ? Self(first: 12, second: 500) : Self()
  }
  mutating func sanitize(_ id: String) {
    let lung = ["lungs", "respiratory"].contains(id)
    first = first.isFinite ? min(lung ? 30 : 160, max(lung ? 6 : 40, first)) : (lung ? 12 : 70)
    second = second.isFinite ? min(lung ? 900 : 120, max(lung ? 200 : 30, second)) : (lung ? 500 : 70)
    phase = phase.isFinite ? min(1, max(0, phase)) : 0
    speed = speed.isFinite ? min(2, max(0.5, speed)) : 1
  }
}

struct GalaxySSIHealthAtlasElimination: Equatable, Codable {
  var halfLife: Double = 4
  var elapsed: Double = 8
  func percent(at hours: Double) -> Double { 100 * pow(0.5, max(0, hours) / max(1, halfLife)) }
  mutating func sanitize() {
    halfLife = halfLife.isFinite ? min(24, max(1, halfLife)) : 4
    elapsed = elapsed.isFinite ? min(48, max(0, elapsed)) : 8
  }
}

enum GalaxySSIHealthAtlasWindow: String, CaseIterable, Codable {
  case week, month, year
  func days(through date: Date, calendar: Calendar) -> Int {
    if self == .week { return 7 }
    let day = calendar.startOfDay(for: date)
    guard let start = calendar.date(byAdding: self == .month ? .month : .year, value: -1, to: day),
      let count = calendar.dateComponents([.day], from: start, to: day).day else { return 7 }
    return min(366, max(1, count))
  }
}

enum GalaxySSIHealthAtlasMetrics {
  static func forEntry(_ id: String) -> [GalaxySSIHealthMetric] {
    switch id {
    case "cardio", "heart", "atria", "ventricles", "heart-valves", "coronary-vessels", "cell-cardiomyocyte":
      return [.bloodPressure, .restingHeartRate, .ldl, .hdl, .triglycerides]
    case "blood-vessels", "arteries", "veins", "capillaries", "cell-vascular-endothelial-cell": return [.bloodPressure, .ldl, .hdl]
    case "pancreas", "pancreatic-islets", "cell-pancreatic-beta-cell", "cell-pancreatic-alpha-cell": return [.glucose, .hba1c]
    case "endocrine": return [.glucose, .hba1c, .tsh]
    case "thyroid-gland", "cell-thyroid-follicular-cell", "cell-thyrotroph": return [.tsh]
    case "liver", "cell-hepatocyte", "digestive": return [.alt, .ast, .albumin, .totalBilirubin]
    case "urinary", "kidneys", "nephron", "glomerulus", "renal-tubules", "collecting-ducts", "cell-podocyte":
      return [.creatinine, .urea, .urineProtein]
    case "respiratory", "lungs", "alveoli", "cell-type-i-pneumocyte", "cell-type-ii-pneumocyte": return [.oxygenSaturation]
    case "blood", "bone-marrow", "immune": return [.hemoglobin, .redBloodCells, .whiteBloodCells, .platelets]
    case "cell-erythrocyte": return [.redBloodCells, .hemoglobin, .hematocrit]
    case "fragment-platelet", "cell-megakaryocyte": return [.platelets]
    case "cell-neutrophil": return [.neutrophilCount, .neutrophilPercent]
    default: return []
    }
  }
}
