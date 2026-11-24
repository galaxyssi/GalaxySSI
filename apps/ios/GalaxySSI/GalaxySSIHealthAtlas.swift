import Foundation
import UIKit

/// Public teaching content only: this graph never loads the health archive.
struct GalaxySSIHealthAtlas: Decodable {
  enum Kind: String, Decodable { case system, organ, tissue, cell, fragment }
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
    var locatedIn: [String]? = nil
    var locations: [String] { locatedIn ?? [] }
    func replacing(mechanism: String? = nil, related: [String]? = nil) -> Self {
      Self(id: id, kind: kind, name: name, description: description, systems: systems, related: related ?? self.related,
        mechanism: mechanism ?? self.mechanism, aliases: aliases, color: color, icon: icon, locatedIn: locatedIn)
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
    guard includeExtensions else { return result }
    try validatePlates([GalaxySSIHealthAtlasEyeOptics.plate], in: result, bundle: bundle)
    if let pack = try ReproductivePack.read(bundle: bundle) { result = try pack.applying(to: result) }
    if let pack = try SystemPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try ArtworkPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try RenalPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try CellPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try RespirationPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try ExtendedCellPack.read(bundle: bundle) { result = try pack.applying(to: result) }
    if let pack = try ImmunePack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    if let pack = try CoreCellPack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    if let pack = try TransportCellPack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    if let pack = try EarPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try TissuePack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try HeartSectionPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try OverviewPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try DigestivePack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try EndocrinePack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try SensoryPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try TissueContextPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try LymphPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try GutPack.read(bundle: bundle) { result = try pack.applying(to: result, bundle: bundle) }
    if let pack = try FunctionStructurePack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    if let pack = try RegionalStructurePack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    if let pack = try DetailStructurePack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }
    return result
  }

  static func validated(_ atlas: Self, requireCompleteMicroscopic: Bool = false) throws -> Self {
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
    let microscopicKinds = ["cell", "fragment"]
    guard atlas.mechanisms.filter({ microscopicKinds.contains($0.kind) }).allSatisfy({ mechanism in
      atlas.entry(mechanism.id).map { $0.kind.rawValue == mechanism.kind && $0.mechanism == mechanism.id } == true
    }), atlas.entries.allSatisfy({ entry in
      !microscopicKinds.contains(atlas.model(entry).kind) || entry.mechanism == entry.id
    }) else { throw Invalid.catalogue }
    if requireCompleteMicroscopic {
      let microscopic = atlas.entries.filter { microscopicKinds.contains($0.kind.rawValue) }
      guard microscopic.allSatisfy({ $0.mechanism == $0.id && atlas.model($0).kind == $0.kind.rawValue }) else { throw Invalid.catalogue }
      let textKeys = microscopic.flatMap { [atlas.model($0).title] + atlas.model($0).stages }
      guard Set(textKeys).count == textKeys.count else { throw Invalid.catalogue }
    }
    guard atlas.entries.allSatisfy({ entry in
      guard entry.kind == .tissue else { return entry.locations.isEmpty && atlas.model(entry).kind != "tissue" }
      return !entry.locations.isEmpty && Set(entry.locations).count == entry.locations.count &&
        entry.locations.allSatisfy { id in
          atlas.entry(id).map { $0.kind == .organ && !$0.systems.filter(entry.systems.contains).isEmpty } == true
        } && !entry.related.isEmpty && Set(entry.related).count == entry.related.count &&
        entry.related.allSatisfy { atlas.entry($0)?.kind == .cell } &&
        entry.mechanism == entry.id && atlas.model(entry).kind == "tissue"
    }), atlas.mechanisms.filter({ $0.kind == "tissue" }).allSatisfy({ atlas.entry($0.id)?.kind == .tissue })
    else { throw Invalid.catalogue }
    return atlas
  }

  func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }
  func model(_ entry: Entry) -> Mechanism { mechanisms.first { $0.id == entry.mechanism }! }
  func children(_ entry: Entry) -> [Entry] { entry.related.compactMap(self.entry) }
  func parents(_ entry: Entry) -> [Entry] {
    (entry.locations.compactMap(self.entry) + entries.filter { $0.kind != .system && $0.related.contains(entry.id) })
      .reduce(into: []) { result, item in if !result.contains(where: { $0.id == item.id }) { result.append(item) } }
  }
  func tissues(_ entry: Entry) -> [Entry] {
    entries.filter { $0.kind == .tissue && (entry.kind == .system ? $0.systems.contains(entry.id) :
      entry.kind == .organ && $0.locations.contains(entry.id)) }
  }
  func cells(_ entry: Entry) -> [Entry] {
    if entry.kind == .tissue { return children(entry) }
    return entries.filter { ($0.kind == .cell || $0.kind == .fragment) &&
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
    var selectorLabel: String? = nil
    var features: [Feature]? = nil
    var splitCallouts: Bool = false
    var annotations: [Feature] { features ?? [] }
    var hasLabels: Bool { !markers.isEmpty || !annotations.isEmpty }
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
        Self.trustedPlateSource(plate.source) &&
        plate.asset.hasPrefix("HealthAtlas") && UIImage(named: plate.asset, in: bundle, compatibleWith: nil) != nil &&
        plate.aspectRatio.isFinite && (0.1...3).contains(plate.aspectRatio) &&
        plate.markers.allSatisfy({ atlas.entry($0.id) != nil && $0.x.isFinite && $0.y.isFinite &&
          (0...1).contains($0.x) && (0...1).contains($0.y) })
      }) else { throw Invalid.catalogue }
  }
  func views(for id: String?) -> [Plate] {
    let context = contextViews(for: id)
    var views = context
    if let detail = DetailStructurePack.plate(for: id) {
      views = [detail] + context.map { locator in
        var value = locator
        if value.viewKey == nil { value.viewKey = "anatomy-locator-" + (value.owner ?? "body") }
        if value.selectorLabel == nil { value.selectorLabel = "health_atlas_locator_view" }
        return value
      }
    }
    guard let id, let pack = try? GutPack.bundled.get(),
      var section = pack.plates.first(where: { $0.owner == id }),
      !views.contains(where: { $0.asset == section.asset }) else { return views }
    section.viewKey = "gut-section-" + id
    section.selectorLabel = section.viewLabel
    return views + [section]
  }
  private func contextViews(for id: String?) -> [Plate] {
    if id == GalaxySSIHealthAtlasRetinaPath.owner, let pack = try? SensoryPack.bundled.get(),
       let layers = pack.plates.first(where: { $0.owner == id }) {
      return [layers, GalaxySSIHealthAtlasRetinaPath.eyeContext]
    }
    if id == "heart" { return [GalaxySSIHealthAtlasHeartSection.exterior, GalaxySSIHealthAtlasHeartSection.section] }
    if let id, let plate = GalaxySSIHealthAtlasHeartSection.plate(for: id) { return [plate] }
    if GalaxySSIHealthAtlasMiddleEar.ids.contains(id ?? "") { return [GalaxySSIHealthAtlasMiddleEar.plate] }
    if id == "cell-tenocyte" {
      let views = RegionalStructurePack.views(for: id)
      if !views.isEmpty { return views }
    }
    if let pack = try? MusculoskeletalPack.bundled.get() {
      let views = pack.plates.filter { $0.entryIDs.contains(id ?? "") }
      if !views.isEmpty {
        let detail = RegionalStructurePack.plate(for: id) ?? FunctionStructurePack.plate(for: id)
        return detail.map { [$0] + views } ?? views
      }
    }
    return defaultPlate(for: id).map { [$0] } ?? []
  }
  static func trustedPlateSource(_ source: URL?) -> Bool {
    guard let source else { return true }
    return source.scheme == "https" && source.user == nil && source.password == nil &&
      (source.host == "openstax.org" || source == GalaxySSIHealthAtlasEyeOptics.anatomySource ||
        source == GalaxySSIHealthAtlasMiddleEar.anatomySource || DigestivePack.paperSources.contains(source) ||
        SensoryPack.externalSources.contains(source) || TissueContextPack.paperSources.contains(source) ||
        RegionalStructurePack.sources.contains(source) || DetailStructurePack.sources.contains(source))
  }
  func plate(for id: String?, viewKey: String? = nil) -> Plate? {
    let available = views(for: id)
    return available.first(where: { $0.viewKey == viewKey }) ?? available.first
  }
  private func defaultPlate(for id: String?) -> Plate? {
    if let plate = RegionalStructurePack.plate(for: id) { return plate }
    if let plate = FunctionStructurePack.plate(for: id) { return plate }
    if let pack = try? GutPack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? LymphPack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? TissueContextPack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? SensoryPack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? OverviewPack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? TissuePack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if GalaxySSIHealthAtlasEyeOptics.plate.entryIDs.contains(id ?? "") { return GalaxySSIHealthAtlasEyeOptics.plate }
    if let pack = try? EndocrinePack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? DigestivePack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? SystemPack.bundled.get(), let plate = pack.plates.first(where: { $0.entryIDs.contains(id ?? "") }) { return plate }
    if let pack = try? ImmunePack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? CoreCellPack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? TransportCellPack.bundled.get(), let plate = pack.plates.first(where: { $0.owner == id }) { return plate }
    if let pack = try? CellPack.bundled.get(), let plate = pack.plates.first(where: { $0.entryIDs.contains(id ?? "") }) { return plate }
    if let pack = try? RenalPack.bundled.get(), pack.plate.entryIDs.contains(id ?? "") { return pack.plate }
    if let pack = try? ArtworkPack.bundled.get() {
      if let plate = pack.plates.first(where: { $0.entryIDs.contains(id ?? "") }) { return plate }
    }
    if ["alveoli", "respiratory-membrane", "pulmonary-capillaries"].contains(id ?? ""),
       let pack = try? RespirationPack.bundled.get() { return pack.plate }
    if id == nil {
      return Plate(id: "whole", asset: "HealthAtlasBody", owner: nil, viewLabel: "health_atlas_illustration", entryIDs: [""],
        aspectRatio: 2.0 / 3.0, markers: [Marker(id: "brain", x: 0.5, y: 0.045), Marker(id: "lungs", x: 0.60, y: 0.24),
          Marker(id: "heart", x: 0.54, y: 0.28),
          Marker(id: "liver", x: 0.45, y: 0.34), Marker(id: "small-intestine", x: 0.51, y: 0.44)])
    }
    if ["heart", "atria", "ventricles", "coronary-vessels"].contains(id ?? "") {
      return GalaxySSIHealthAtlasHeartSection.exterior
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
    if key == "health_atlas_belongs" {
      let english = localized(key, locale: "en", fallback: localized(key, locale: "en", fallback: key), table: "AtlasFunction")
      return regional(key, locale: name, fallback: localized(key, locale: name, fallback: english, table: "AtlasFunction"))
    }
    let organ = try? GalaxySSIHealthAtlas.ArtworkPack.bundled.get()
    let cells = try? GalaxySSIHealthAtlas.CellPack.bundled.get()
    let systems = try? GalaxySSIHealthAtlas.SystemPack.bundled.get()
    let extensionText = systems?.english[key] ?? cells?.english[key] ?? organ?.english[key]
    let english = extensionText ?? localized(key, locale: "en", fallback: localized(key, locale: "en", fallback: key, table: "AtlasFunction"))
    let fallback = localized(key, locale: name, fallback: english, table: "AtlasFunction")
    return regional(key, locale: name, fallback: localized(key, locale: name, fallback: fallback, table: extensionText == nil ? "BodyAtlas" : "Localizable"))
  }
  private static func regional(_ key: String, locale: String, fallback: String) -> String {
    let english = localized(key, locale: "en", fallback: fallback, table: "AtlasRegional")
    let prior = localized(key, locale: locale, fallback: english, table: "AtlasRegional")
    let completeEnglish = localized(key, locale: "en", fallback: prior, table: "AtlasComplete")
    let complete = localized(key, locale: locale, fallback: completeEnglish, table: "AtlasComplete")
    let detailEnglish = localized(key, locale: "en", fallback: complete, table: "AtlasDetail")
    let detail = localized(key, locale: locale, fallback: detailEnglish, table: "AtlasDetail")
    let expandedEnglish = localized(key, locale: "en", fallback: detail, table: "AtlasExpanded")
    let expanded = localized(key, locale: locale, fallback: expandedEnglish, table: "AtlasExpanded")
    let anatomyEnglish = localized(key, locale: "en", fallback: expanded, table: "AtlasAnatomy")
    let anatomy = localized(key, locale: locale, fallback: anatomyEnglish, table: "AtlasAnatomy")
    let teachingEnglish = localized(key, locale: "en", fallback: anatomy, table: "AtlasTeaching")
    let teaching = localized(key, locale: locale, fallback: teachingEnglish, table: "AtlasTeaching")
    let systemEnglish = localized(key, locale: "en", fallback: teaching, table: "AtlasSystemTeaching")
    let system = localized(key, locale: locale, fallback: systemEnglish, table: "AtlasSystemTeaching")
    let organEnglish = localized(key, locale: "en", fallback: system, table: "AtlasOrganTeaching")
    let organ = localized(key, locale: locale, fallback: organEnglish, table: "AtlasOrganTeaching")
    let regionalEnglish = localized(key, locale: "en", fallback: organ, table: "AtlasRegionalTeaching")
    let regional = localized(key, locale: locale, fallback: regionalEnglish, table: "AtlasRegionalTeaching")
    let transportEnglish = localized(key, locale: "en", fallback: regional, table: "AtlasTransportTeaching")
    let transport = localized(key, locale: locale, fallback: transportEnglish, table: "AtlasTransportTeaching")
    let phaseEnglish = localized(key, locale: "en", fallback: transport, table: "AtlasPhaseTeaching")
    let phase = localized(key, locale: locale, fallback: phaseEnglish, table: "AtlasPhaseTeaching")
    let exchangeEnglish = localized(key, locale: "en", fallback: phase, table: "AtlasExchangeTeaching")
    let exchange = localized(key, locale: locale, fallback: exchangeEnglish, table: "AtlasExchangeTeaching")
    let pleuralEnglish = localized(key, locale: "en", fallback: exchange, table: "AtlasPleuralTeaching")
    let pleural = localized(key, locale: locale, fallback: pleuralEnglish, table: "AtlasPleuralTeaching")
    let completionEnglish = localized(key, locale: "en", fallback: pleural, table: "AtlasCompletionTeaching")
    let completion = localized(key, locale: locale, fallback: completionEnglish, table: "AtlasCompletionTeaching")
    let actionsEnglish = localized(key, locale: "en", fallback: completion, table: "AtlasWholeActions")
    let actions = localized(key, locale: locale, fallback: actionsEnglish, table: "AtlasWholeActions")
    let readingsEnglish = localized(key, locale: "en", fallback: actions, table: "AtlasRelatedReadings")
    let readings = localized(key, locale: locale, fallback: readingsEnglish, table: "AtlasRelatedReadings")
    let comparisonEnglish = localized(key, locale: "en", fallback: readings, table: "AtlasModelComparison")
    let comparison = localized(key, locale: locale, fallback: comparisonEnglish, table: "AtlasModelComparison")
    let guidedEnglish = localized(key, locale: "en", fallback: comparison, table: "AtlasGuidedFunction")
    let guided = localized(key, locale: locale, fallback: guidedEnglish, table: "AtlasGuidedFunction")
    let cumulativeEnglish = localized(key, locale: "en", fallback: guided, table: "AtlasCumulativeComparison")
    let cumulative = localized(key, locale: locale, fallback: cumulativeEnglish, table: "AtlasCumulativeComparison")
    let researchEnglish = localized(key, locale: "en", fallback: cumulative, table: "AtlasResearchNavigation")
    let research = localized(key, locale: locale, fallback: researchEnglish, table: "AtlasResearchNavigation")
    let sceneEnglish = localized(key, locale: "en", fallback: research, table: "AtlasSynchronizedLessons")
    let scenes = localized(key, locale: locale, fallback: sceneEnglish, table: "AtlasSynchronizedLessons")
    let closeupEnglish = localized(key, locale: "en", fallback: scenes, table: "AtlasMechanismCloseups")
    return localized(key, locale: locale, fallback: closeupEnglish, table: "AtlasMechanismCloseups")
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
    case "urinary", "kidneys", "renal-cortex", "renal-medulla", "renal-pelvis", "nephron", "glomerulus",
         "renal-tubules", "collecting-ducts", "cell-podocyte", "bowmans-capsule", "proximal-tubule", "nephron-loop", "distal-tubule":
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
