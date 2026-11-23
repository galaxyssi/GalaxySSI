import Foundation
import UIKit

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
    func replacing(mechanism: String? = nil, related: [String]? = nil) -> Self {
      Self(id: id, kind: kind, name: name, description: description, systems: systems, related: related ?? self.related,
        mechanism: mechanism ?? self.mechanism, aliases: aliases, color: color, icon: icon)
    }
  }
  struct Mechanism: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let stages: [String]
    let chapter: String
    var reference: URL? = nil
    var source: URL { reference ?? URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/" + chapter)! }
  }
  let schema: Int
  let entries: [Entry]
  let mechanisms: [Mechanism]
  enum Invalid: Error { case catalogue }

  static func load(bundle: Bundle = .main, includeExtensions: Bool = true) throws -> Self {
    guard let url = bundle.url(forResource: "body-atlas", withExtension: "json", subdirectory: "body-atlas")
    else { throw Invalid.catalogue }
    var result = try validated(JSONDecoder().decode(Self.self, from: Data(contentsOf: url)))
    if includeExtensions, let pack = try MusculoskeletalPack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    if includeExtensions, let pack = try OverviewPack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    guard includeExtensions else { return result }
    if let pack = try SystemPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try ArtworkPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try RenalPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try CellPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    return try RespirationPack.read(bundle: bundle)?.applying(to: result, bundle: bundle) ?? result
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
        (model.reference == nil || model.reference!.absoluteString.range(of: "^https://pubmed\\.ncbi\\.nlm\\.nih\\.gov/[1-9][0-9]*/$", options: .regularExpression) != nil) &&
        model.chapter.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
      }) else { throw Invalid.catalogue }
    guard atlas.mechanisms.filter({ $0.kind == "cell" }).allSatisfy({ mechanism in
      atlas.entry(mechanism.id).map { $0.kind == .cell && $0.mechanism == mechanism.id } == true
    }), atlas.entries.allSatisfy({ entry in
      atlas.model(entry).kind != "cell" || entry.mechanism == entry.id
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

  struct Marker: Decodable {
    let id: String
    let x: Double
    let y: Double
  }
  struct Plate: Decodable {
    let id: String
    let asset: String
    let owner: String?
    let viewLabel: String
    let entryIDs: [String]
    let aspectRatio: Double
    let markers: [Marker]
    var source: URL? = nil
    var viewKey: String? = nil
  }
  /// An additive, bundled-only asset pack can land independently of the atlas UI.
  struct ArtworkPack: Decodable {
    let schema: Int
    let entries: [Entry]
    let insertAfter: [String: String]
    let relatedAdditions: [String: [String]]
    let plates: [Plate]
    let english: [String: String]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }

    static func read(bundle: Bundle) throws -> Self? {
      guard let asset = NSDataAsset(name: "HealthAtlasOrganPlates", bundle: bundle) else { return nil }
      guard asset.data.count <= 256_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: asset.data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let existing = Set(base.entries.map(\.id)), additions = Set(entries.map(\.id))
      guard schema == 1, entries.count <= 100, additions.count == entries.count,
        additions.isDisjoint(with: existing), Set(insertAfter.keys) == additions,
        insertAfter.values.allSatisfy(existing.contains), relatedAdditions.keys.allSatisfy(existing.contains),
        english.count <= 1000, english.keys.allSatisfy({ $0.hasPrefix("health_atlas_") }) else { throw Invalid.catalogue }
      let combined = base.entries.flatMap { entry -> [Entry] in
        let related = (relatedAdditions[entry.id] ?? []).filter { !entry.related.contains($0) } + entry.related
        let revised = entry.replacing(related: related)
        return [revised] + entries.filter { insertAfter[$0.id] == entry.id }
      }
      let result = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: combined, mechanisms: base.mechanisms))
      try GalaxySSIHealthAtlas.validatePlates(plates, in: result, bundle: bundle)
      return result
    }
  }
  struct CellPack: Decodable {
    let schema: Int
    let mechanisms: [Mechanism]
    let entryMechanisms: [String: String]
    let plates: [Plate]
    let english: [String: String]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let asset = NSDataAsset(name: "HealthAtlasCellProcesses", bundle: bundle) else { return nil }
      guard asset.data.count <= 512_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: asset.data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      let ids = Set(mechanisms.map(\.id))
      guard schema == 1, !mechanisms.isEmpty, mechanisms.count <= 300, ids.count == mechanisms.count, Set(entryMechanisms.keys) == ids,
        Set(entryMechanisms.values) == ids, entryMechanisms.allSatisfy({ $0.key == $0.value && base.entry($0.key)?.kind == .cell }),
        mechanisms.allSatisfy({ $0.kind == "cell" }), ids.isDisjoint(with: Set(base.mechanisms.map(\.id))),
        english.count <= 2000, english.keys.allSatisfy({ $0.hasPrefix("health_atlas_process_") || $0.hasPrefix("health_atlas_view_") })
      else { throw Invalid.catalogue }
      let revised = base.entries.map { $0.replacing(mechanism: entryMechanisms[$0.id]) }
      let result = try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: revised, mechanisms: base.mechanisms + mechanisms))
      try GalaxySSIHealthAtlas.validatePlates(plates, in: result, bundle: bundle)
      guard plates.allSatisfy({ plate in
        plate.owner.map { result.entry($0)?.kind == .cell && plate.entryIDs == [$0] } == true
      }) else { throw Invalid.catalogue }
      return result
    }
  }
  struct SystemPack: Decodable {
    let schema: Int
    let plates: [Plate]
    let english: [String: String]
    static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
    static func read(bundle: Bundle) throws -> Self? {
      guard let asset = NSDataAsset(name: "HealthAtlasSystemPlates", bundle: bundle) else { return nil }
      guard asset.data.count <= 128_000 else { throw Invalid.catalogue }
      return try JSONDecoder().decode(Self.self, from: asset.data)
    }
    func applying(to base: GalaxySSIHealthAtlas, bundle: Bundle) throws -> GalaxySSIHealthAtlas {
      guard schema == 1, !plates.isEmpty, english.count <= 128, english.values.allSatisfy({ !$0.isEmpty }),
        english.keys.allSatisfy({ $0.hasPrefix("health_atlas_view_") || $0 == "health_atlas_plate_source" }) else { throw Invalid.catalogue }
      try GalaxySSIHealthAtlas.validatePlates(plates, in: base, bundle: bundle)
      guard plates.allSatisfy({ plate in
        guard let owner = plate.owner, let entry = base.entry(owner), entry.kind == .system || entry.kind == .organ,
          plate.entryIDs.contains(owner), plate.source != nil, english[plate.viewLabel] != nil else { return false }
        let visible = Set(plate.markers.map(\.id) + [owner])
        return plate.entryIDs.allSatisfy { visible.contains($0) && base.entry($0)?.kind != .cell && base.entry($0)?.kind != .fragment }
      }) else { throw Invalid.catalogue }
      return base
    }
  }
  private static func validatePlates(_ plates: [Plate], in atlas: Self, bundle: Bundle) throws {
    guard plates.count <= 64, Set(plates.map(\.id)).count == plates.count,
      Set(plates.flatMap(\.entryIDs)).count == plates.flatMap(\.entryIDs).count,
      plates.allSatisfy({ plate in
        !plate.entryIDs.isEmpty && plate.entryIDs.allSatisfy({ $0.isEmpty || atlas.entry($0) != nil }) &&
        (plate.owner == nil || atlas.entry(plate.owner!) != nil) &&
        (plate.source == nil || (plate.source?.scheme == "https" && plate.source?.host == "openstax.org" &&
          plate.source?.user == nil && plate.source?.password == nil)) &&
        plate.asset.hasPrefix("HealthAtlas") && UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil &&
        plate.aspectRatio.isFinite && (0.1...3).contains(plate.aspectRatio) &&
        plate.markers.allSatisfy({ atlas.entry($0.id) != nil && $0.x.isFinite && $0.y.isFinite &&
          (0...1).contains($0.x) && (0...1).contains($0.y) })
      }) else { throw Invalid.catalogue }
  }
  func views(for id: String?) -> [Plate] {
    if let pack = try? MusculoskeletalPack.bundled.get() {
      let views = pack.plates.filter { $0.entryIDs.contains(id ?? "") }
      if !views.isEmpty { return views }
    }
    return defaultPlate(for: id).map { [$0] } ?? []
  }
  func plate(for id: String?, viewKey: String? = nil) -> Plate? {
    let available = views(for: id)
    return available.first(where: { $0.viewKey == viewKey }) ?? available.first
  }
  private func defaultPlate(for id: String?) -> Plate? {
    if let pack = try? SystemPack.bundled.get(), let plate = pack.plates.first(where: { $0.entryIDs.contains(id ?? "") }) { return plate }
    if let pack = try? CellPack.bundled.get(), let plate = pack.plates.first(where: { $0.entryIDs.contains(id ?? "") }) { return plate }
    if let pack = try? RenalPack.bundled.get(), pack.plate.entryIDs.contains(id ?? "") { return pack.plate }
    if let pack = try? ArtworkPack.bundled.get() {
      if let plate = pack.plates.first(where: { $0.entryIDs.contains(id ?? "") }) { return plate }
    }
    if ["alveoli", "respiratory-membrane", "pulmonary-capillaries"].contains(id ?? ""),
       let pack = try? RespirationPack.bundled.get() { return pack.plate }
    if id == nil {
      return Plate(id: "whole", asset: "HealthAtlasBody", owner: nil, viewLabel: "health_atlas_illustration", entryIDs: [""],
        aspectRatio: 2.0 / 3.0, markers: [Marker(id: "brain", x: 0.5, y: 0.045), Marker(id: "heart", x: 0.54, y: 0.28),
          Marker(id: "liver", x: 0.45, y: 0.34), Marker(id: "small-intestine", x: 0.51, y: 0.44)])
    }
    if ["heart", "cardio", "atria", "ventricles", "heart-valves", "coronary-vessels"].contains(id ?? "") {
      return Plate(id: "heart", asset: "HealthAtlasHeart", owner: "heart", viewLabel: "health_atlas_illustration", entryIDs: [id!],
        aspectRatio: 3.0 / 4.0, markers: [Marker(id: "atria", x: 0.28, y: 0.46), Marker(id: "coronary-vessels", x: 0.57, y: 0.68),
          Marker(id: "ventricles", x: 0.61, y: 0.84)])
    }
    if id == "cell-pancreatic-beta-cell" {
      return Plate(id: "beta-cell", asset: "HealthAtlasBetaCell", owner: id, viewLabel: "health_atlas_illustration",
        entryIDs: [id!], aspectRatio: 1, markers: [])
    }
    if let pack = try? OverviewPack.bundled.get() { return pack.plates.first { $0.entryIDs.contains(id ?? "") } }
    return nil
  }
  func caption(_ plate: Plate, selected entry: Entry?, language: String) -> String {
    let view = GalaxySSIHealthAtlasText.get(plate.viewLabel, language)
    guard let owner = plate.owner, owner != entry?.id, let structure = self.entry(owner) else { return view }
    let name = GalaxySSIHealthAtlasText.get(structure.name, language)
    let key = plate.viewLabel == "health_atlas_illustration" ? "health_atlas_related_process" : "health_atlas_plate_context"
    return String(format: GalaxySSIHealthAtlasText.get(key, language), name, view)
  }
}

enum GalaxySSIHealthAtlasText {
  static func get(_ key: String, _ language: String) -> String {
    let name = LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en"
    let organ = try? GalaxySSIHealthAtlas.ArtworkPack.bundled.get()
    let cells = try? GalaxySSIHealthAtlas.CellPack.bundled.get()
    let systems = try? GalaxySSIHealthAtlas.SystemPack.bundled.get()
    let extensionText = systems?.english[key] ?? cells?.english[key] ?? organ?.english[key]
    let english = extensionText ?? localized(key, locale: "en", fallback: key)
    return localized(key, locale: name, fallback: english, table: extensionText == nil ? "BodyAtlas" : "Localizable")
  }
  private static func localized(_ key: String, locale: String, fallback: String, table: String = "BodyAtlas") -> String {
    guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
    return locale == "en" && table == "Localizable" ? fallback : bundle.localizedString(forKey: key, value: fallback, table: table)
  }
}

struct GalaxySSIHealthAtlasSimulation: Equatable, Codable {
  var first: Double = 70
  var second: Double = 70
  var phase: Double = 0
  var speed: Double = 1
  var stage: Int { min(3, max(0, Int(phase * 4))) }
  var output: Double { first * second / 1000 }
  @discardableResult mutating func selectStage(_ index: Int) -> Bool {
    guard (0..<4).contains(index) else { return false }
    phase = Double(index) / 4
    return true
  }
  static func initial(_ id: String) -> Self {
    ["lungs", "respiratory", "alveoli"].contains(id) ? Self(first: 12, second: 500) : Self()
  }
  mutating func sanitize(_ id: String) {
    let lung = ["lungs", "respiratory", "alveoli"].contains(id)
    first = first.isFinite ? min(lung ? 30 : 160, max(lung ? 6 : 40, first.rounded())) : (lung ? 12 : 70)
    second = second.isFinite ? min(lung ? 900 : 120, max(lung ? 200 : 30, second.rounded())) : (lung ? 500 : 70)
    phase = phase.isFinite ? min(1, max(0, phase)) : 0
    speed = speed.isFinite ? min(2, max(0.5, speed)) : 1
  }
}

struct GalaxySSIHealthAtlasElimination: Equatable, Codable {
  var halfLife: Double = 4
  var elapsed: Double = 8
  func percent(at hours: Double) -> Double { 100 * pow(0.5, max(0, hours) / max(1, halfLife)) }
  mutating func sanitize() {
    halfLife = halfLife.isFinite ? min(24, max(1, halfLife.rounded())) : 4
    elapsed = elapsed.isFinite ? min(48, max(0, elapsed.rounded())) : 8
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
    case "respiratory", "lungs", "alveoli", "respiratory-membrane", "pulmonary-capillaries",
         "cell-type-i-pneumocyte", "cell-type-ii-pneumocyte": return [.oxygenSaturation]
    case "blood", "bone-marrow", "immune": return [.hemoglobin, .redBloodCells, .whiteBloodCells, .platelets]
    case "cell-erythrocyte": return [.redBloodCells, .hemoglobin, .hematocrit]
    case "fragment-platelet", "cell-megakaryocyte": return [.platelets]
    case "cell-neutrophil": return [.neutrophilCount, .neutrophilPercent]
    default: return []
    }
  }
}
