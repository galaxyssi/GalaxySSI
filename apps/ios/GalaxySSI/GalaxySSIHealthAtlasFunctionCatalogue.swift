import Foundation
import UIKit

struct GalaxySSIHealthAtlasFunctionCatalogue: Decodable {
  struct Source: Decodable { let androidPR: Int; let mergeCommit: String }
  struct Chapter: Decodable, Equatable { let title: String; let caption: String }
  struct Reference: Decodable, Equatable { let title: String; let url: URL }
  struct Related: Decodable, Equatable { let entryID: String; let storyID: String }
  struct Story: Decodable, Identifiable, Equatable {
    let id: String
    let owners: [String]
    let title: String
    let choiceTitle: String
    let scope: String
    let chapters: [Chapter]
    let references: [Reference]
    let durationMs: Int
    let showStructurePreview: Bool
    let related: [Related]
    func chapter(_ value: Double) -> Int { min(chapters.count - 1, Int(Self.safePhase(value) * Double(chapters.count))) }
    func fraction(_ value: Double) -> Double { min(1, max(0, Self.safePhase(value) * Double(chapters.count) - Double(chapter(value)))) }
    func startOf(_ index: Int) -> Double { Double(min(chapters.count - 1, max(0, index))) / Double(chapters.count) }
    static func safePhase(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
  }
  let schema: Int
  let source: Source
  let stories: [Story]
  let routes: [String: [String]]
  let entryPhases: [String: [String: Double]]
  static let bundled: Result<Self?, Error> = Result { try read(bundle: .main) }
  static func read(bundle: Bundle, revision: Int = 4385) throws -> Self? {
    guard [4384, 4385, 4388].contains(revision) else { throw GalaxySSIHealthAtlas.Invalid.catalogue }
    let asset = revision == 4384 ? "HealthAtlasFunctionStories" : revision == 4385 ? "HealthAtlasRegionalStories" : "HealthAtlasCompleteStories"
    guard let data = NSDataAsset(name: asset, bundle: bundle)?.data else { return nil }
    guard data.count <= 1_000_000 else { throw GalaxySSIHealthAtlas.Invalid.catalogue }
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.source.androidPR == revision else { throw GalaxySSIHealthAtlas.Invalid.catalogue }
    try value.validate()
    return value
  }
  func story(_ id: String) -> Story? { stories.first { $0.id == id } }
  func choices(for entryID: String) -> [Story] { (routes[entryID] ?? []).compactMap(story) }
  func initialPhase(entryID: String, storyID: String) -> Double { entryPhases[entryID]?[storyID] ?? 0 }
  func validate() throws {
    let ids = Set(stories.map(\.id))
    let owners = Set(stories.flatMap(\.owners))
    func key(_ value: String) -> Bool { value.hasPrefix("health_atlas_") && value.count <= 128 && !value.contains(where: \.isWhitespace) }
    let baseline = source.androidPR == 4384 && source.mergeCommit == "ab78711d467c013444883dbaeca23c39a601c875" &&
      stories.count == 101 && stories.reduce(0, { $0 + $1.chapters.count }) == 491 && routes.count == 268 &&
      stories.reduce(0, { $0 + $1.references.count }) == 226
    let regional = source.androidPR == 4385 && source.mergeCommit == "a81aa85a1c81e41ff19a032eabea1eddcd2371dc" &&
      stories.count == 114 && stories.reduce(0, { $0 + $1.chapters.count }) == 544 && routes.count == 289 &&
      stories.reduce(0, { $0 + $1.references.count }) == 261
    let complete = source.androidPR == 4388 && source.mergeCommit == "6581110ec5c048edebf63821dee839b4818fe663" &&
      stories.count == 138 && stories.reduce(0, { $0 + $1.chapters.count }) == 643 && routes.count == 313 &&
      stories.reduce(0, { $0 + $1.references.count }) == 320
    guard schema == 1, baseline || regional || complete, ids.count == stories.count,
      Set(routes.keys) == owners, Set(entryPhases.keys) == owners,
      stories.allSatisfy({ story in
        !story.id.isEmpty && story.id.count <= 80 && story.id.allSatisfy({ $0.isUppercase || $0 == "_" || $0.isNumber }) &&
          !story.owners.isEmpty && Set(story.owners).count == story.owners.count &&
          [story.title, story.choiceTitle, story.scope].allSatisfy(key) &&
          (3...5).contains(story.chapters.count) && (1...120_000).contains(story.durationMs) &&
          story.chapters.allSatisfy({ key($0.title) && key($0.caption) }) &&
          !story.references.isEmpty && story.references.allSatisfy({ key($0.title) && Self.trusted($0.url) }) &&
          story.related.allSatisfy({ routes[$0.entryID]?.contains($0.storyID) == true })
      }),
      routes.allSatisfy({ entryID, choices in
        !entryID.isEmpty && !choices.isEmpty && choices.count <= 6 && Set(choices).count == choices.count &&
          Set(choices).isSubset(of: ids) && Set(entryPhases[entryID]?.keys.map { $0 } ?? []) == Set(choices) &&
          (entryPhases[entryID]?.values.allSatisfy { $0.isFinite && (0...1).contains($0) } ?? false)
      })
    else { throw GalaxySSIHealthAtlas.Invalid.catalogue }
  }
  func validate(in atlas: GalaxySSIHealthAtlas) throws {
    try validate()
    guard routes.keys.allSatisfy({ atlas.entry($0) != nil }) else { throw GalaxySSIHealthAtlas.Invalid.catalogue }
  }
  private static func trusted(_ url: URL) -> Bool {
    let hosts: Set<String> = ["pubmed.ncbi.nlm.nih.gov", "pmc.ncbi.nlm.nih.gov", "openstax.org", "www.nhlbi.nih.gov",
      "www.niddk.nih.gov", "www.nidcd.nih.gov", "www.nei.nih.gov", "www.ncbi.nlm.nih.gov", "doi.org", "www.nature.com",
      "www.jci.org", "link.springer.com", "pure.amsterdamumc.nl", "journals.plos.org", "www.jstage.jst.go.jp",
      "nba.uth.tmc.edu", "temple.manifoldapp.org", "hdl.handle.net", "histology.leeds.ac.uk", "tales.nmc.unibas.ch",
      "training.seer.cancer.gov", "www.medcell.org", "sti.bmj.com", "rad.washington.edu",
      "www.pnas.org", "histology.oit.duke.edu", "jcp.bmj.com", "www.nichd.nih.gov", "open.umich.edu", "biomedizin.unibas.ch"]
    return url.scheme == "https" && url.host.map(hosts.contains) == true && url.user == nil && url.password == nil && url.port == nil
  }
}

struct GalaxySSIHealthAtlasFunctionSelection: Codable, Equatable {
  private enum CodingKeys: String, CodingKey { case selected, phases }
  var selected: String?
  var phases: [String: Double] = [:]
  func current(entryID: String, catalogue: GalaxySSIHealthAtlasFunctionCatalogue) -> GalaxySSIHealthAtlasFunctionCatalogue.Story? {
    let choices = catalogue.choices(for: entryID)
    return choices.first { $0.id == selected } ?? choices.first
  }
  func phase(entryID: String, storyID: String, catalogue: GalaxySSIHealthAtlasFunctionCatalogue) -> Double {
    guard catalogue.routes[entryID]?.contains(storyID) == true else { return 0 }
    return phases[storyID].map(GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase) ?? catalogue.initialPhase(entryID: entryID, storyID: storyID)
  }
  mutating func choose(_ storyID: String, entryID: String, catalogue: GalaxySSIHealthAtlasFunctionCatalogue) {
    if catalogue.routes[entryID]?.contains(storyID) == true { selected = storyID }
  }
  mutating func save(_ phase: Double, storyID: String, entryID: String, catalogue: GalaxySSIHealthAtlasFunctionCatalogue) {
    if catalogue.routes[entryID]?.contains(storyID) == true { phases[storyID] = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(phase) }
  }
  mutating func sanitize(entryID: String, catalogue: GalaxySSIHealthAtlasFunctionCatalogue) {
    let allowed = Set(catalogue.routes[entryID] ?? [])
    if let selected, !allowed.contains(selected) { self.selected = nil }
    phases = phases.filter { allowed.contains($0.key) }.mapValues(GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase)
  }
}

extension GalaxySSIHealthAtlasFunctionSelection {
  init(from decoder: Decoder) throws {
    guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
      selected = nil; phases = [:]; return
    }
    selected = try? values.decode(String.self, forKey: .selected)
    phases = (try? values.decode([String: Double].self, forKey: .phases)) ?? [:]
  }
}
