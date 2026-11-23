import XCTest
import UIKit
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAtlasTests: XCTestCase {
  private func catalogue() throws -> GalaxySSIHealthAtlas {
    try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self), includeExtensions: false)
  }
  private func completeCatalogue() throws -> GalaxySSIHealthAtlas {
    try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
  }

  func testRenalPackPreservesCanonicalStructuresAndOwnedCellProcesses() throws {
    let bundle = Bundle(for: GalaxySSIStore.self)
    let base = try catalogue()
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.RenalPack.read(bundle: bundle))
    let atlas = try pack.applying(to: base, bundle: bundle)
    XCTAssertEqual(atlas.entries.count, base.entries.count + 4)
    XCTAssertEqual(atlas.mechanisms.count, base.mechanisms.count + 7)
    for id in ["bowmans-capsule", "proximal-tubule", "nephron-loop", "distal-tubule"] {
      XCTAssertEqual(atlas.entry(id)?.kind, .organ)
      XCTAssertEqual(atlas.entry(id)?.systems, ["urinary"])
    }
    for model in pack.mechanisms {
      XCTAssertEqual(model.kind, "cell")
      XCTAssertEqual(atlas.entry(model.id)?.mechanism, model.id)
      XCTAssertEqual(atlas.entry(model.id)?.kind, .cell)
      XCTAssertEqual(model.stages.count, 4)
    }
    XCTAssertEqual(pack.plate.entryIDs.count, 8)
    XCTAssertEqual(pack.plate.markers.count, 6)
    XCTAssertEqual(pack.plate.source?.host, "openstax.org")
    XCTAssertFalse(pack.plate.entryIDs.contains("kidneys"))
    XCTAssertFalse(pack.plate.entryIDs.contains("cell-podocyte"))
    XCTAssertThrowsError(try pack.applying(to: atlas, bundle: bundle))
  }

  func testDrugStateRestorationPreservesBothModelsAndLegacySelections() throws {
    let atlas = try catalogue()
    let legacy = GalaxySSIHealthAtlasState.Selection()
    let legacyData = try JSONEncoder().encode(["heart": legacy])
    let restored = GalaxySSIHealthAtlasState()
    restored.restore(try XCTUnwrap(String(data: legacyData, encoding: .utf8)), atlas: atlas)
    XCTAssertNotNil(restored.entries["heart"])
    XCTAssertNil(restored.entries["heart"]?.drugInputs)
    var selection = legacy
    selection.research = .drugs
    selection.elimination.halfLife = 7
    selection.elimination.elapsed = 13
    let distribution = try XCTUnwrap(GalaxySSIHealthAtlasDistribution(outward: 100, returning: 50, elimination: 20, quarterHours: 47))
    var drugs = GalaxySSIHealthAtlasDrugState(mode: .two, distribution: distribution)
    drugs.mode = .single
    selection.drugInputs = drugs.encoded
    restored.entries["heart"] = selection
    let next = GalaxySSIHealthAtlasState()
    next.restore(restored.serialized, atlas: atlas)
    let roundTrip = try XCTUnwrap(next.entries["heart"])
    XCTAssertEqual(roundTrip.elimination, selection.elimination)
    XCTAssertEqual(GalaxySSIHealthAtlasDrugState.restore(roundTrip.drugInputs), drugs)
    for invalid in [[2, 30, 15, 10, 16], [1, 301, 15, 10, 16], []] {
      selection.drugInputs = invalid
      restored.entries["heart"] = selection
      next.restore(restored.serialized, atlas: atlas)
      XCTAssertNil(next.entries["heart"]?.drugInputs)
      XCTAssertEqual(next.entries["heart"]?.elimination, selection.elimination)
      XCTAssertEqual(next.entries["heart"]?.research, .drugs)
    }
  }

  func testFrozenCatalogueCountsAndCanonicalGraph() throws {
    let atlas = try catalogue()
    XCTAssertEqual(atlas.entries.count, 278)
    XCTAssertEqual(atlas.mechanisms.count, 20)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .system }.count, 14)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .organ }.count, 158)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .cell }.count, 105)
    XCTAssertEqual(atlas.entries.filter { $0.kind == .fragment }.map(\.id), ["fragment-platelet"])
    for entry in atlas.entries {
      XCTAssertTrue(entry.related.allSatisfy { atlas.entry($0) != nil })
      XCTAssertEqual(atlas.model(entry).stages.count, 4)
      XCTAssertEqual(atlas.model(entry).source.host, "openstax.org")
    }
    XCTAssertTrue(atlas.cells(try XCTUnwrap(atlas.entry("cardio"))).contains { $0.id == "cell-cardiomyocyte" })
    XCTAssertTrue(atlas.parents(try XCTUnwrap(atlas.entry("ventricles"))).contains { $0.id == "heart" })
  }

  func testGasExchangeExamplesAreFixedAndMoveInOppositeDirections() {
    typealias Gas = GalaxySSIHealthAtlasGasExchange
    XCTAssertEqual(Gas.gradients.map(\.alveolar), [104, 40])
    XCTAssertEqual(Gas.gradients.map(\.incomingBlood), [40, 45])
    XCTAssertEqual(Gas.gradients.map(\.towardBlood), [true, false])
    XCTAssertEqual(Gas.gradients.map(\.difference), [64, 5])
    XCTAssertEqual(Gas.stage(.nan), 0); XCTAssertEqual(Gas.stage(.infinity), 0)
    XCTAssertEqual(Gas.stage(-1), 0); XCTAssertEqual(Gas.stage(1), 3)
    XCTAssertEqual(Gas.position(.oxygen, phase: 0.25), 0.25)
    XCTAssertEqual(Gas.position(.carbon, phase: 0.25), 0.75)
    for id in ["alveoli", "respiratory-membrane", "pulmonary-capillaries"] { XCTAssertTrue(Gas.supports(id)) }
    for id in ["lungs", "cell-type-i-pneumocyte", "blood"] { XCTAssertFalse(Gas.supports(id)) }
    XCTAssertEqual(GalaxySSIHealthAtlasSimulation.initial("alveoli").first, 12)
    XCTAssertEqual(GalaxySSIHealthAtlasSimulation.initial("alveoli").second, 500)
    XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry("respiratory-membrane"), [.oxygenSaturation])
  }

  func testEveryCatalogueKeyResolvesInBothLanguagesWithoutAndroidQuoteDelimiters() throws {
    let atlas = try catalogue()
    let keys = atlas.entries.flatMap { [$0.name, $0.description, $0.aliases] } + atlas.mechanisms.flatMap { [$0.title] + $0.stages }
    for language in ["en", "zh-Hans"] {
      for key in keys {
        let value = GalaxySSIHealthAtlasText.get(key, language)
        XCTAssertNotEqual(value, key, key)
        XCTAssertFalse(value.hasPrefix("\""), key)
      }
    }
    XCTAssertNotEqual(GalaxySSIHealthAtlasText.get("health_atlas_heart_name", "en"),
      GalaxySSIHealthAtlasText.get("health_atlas_heart_name", "zh-Hans"))
  }

  func testRespirationPackLoadsCanonicalGasRoutesAndHumanClubCellReference() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    for id in ["alveoli", "respiratory-membrane", "pulmonary-capillaries"] {
      let entry = try XCTUnwrap(atlas.entry(id))
      XCTAssertEqual(entry.mechanism, "gas-exchange")
      XCTAssertEqual(atlas.plate(for: id)?.id, "alveolus")
    }
    let club = try XCTUnwrap(atlas.entry("cell-club-cell"))
    XCTAssertEqual(atlas.model(club).source.absoluteString, "https://pubmed.ncbi.nlm.nih.gov/29874100/")
    XCTAssertEqual(atlas.model(club).stages.count, 4)
    XCTAssertNil(atlas.plate(for: club.id))
  }

  func testMechanismResearchReferencesCannotEscapePubMedArticleAllowlist() throws {
    let base = try catalogue()
    let original = try XCTUnwrap(base.mechanisms.first)
    for address in ["https://pubmed.ncbi.nlm.nih.gov/29874100/", "https://example.com/29874100/",
      "http://pubmed.ncbi.nlm.nih.gov/29874100/", "https://pubmed.ncbi.nlm.nih.gov/0/",
      "https://pubmed.ncbi.nlm.nih.gov/29874100/?token=private"] {
      var model = original
      model.reference = URL(string: address)
      let candidate = GalaxySSIHealthAtlas(schema: base.schema, entries: base.entries, mechanisms: [model] + base.mechanisms.dropFirst())
      if address == "https://pubmed.ncbi.nlm.nih.gov/29874100/" {
        XCTAssertNoThrow(try GalaxySSIHealthAtlas.validated(candidate))
        XCTAssertEqual(model.source.absoluteString, address)
      } else { XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(candidate)) }
    }
  }

  func testMusculoskeletalViewsOnlyExposeVisibleSurfaceStructures() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    XCTAssertEqual(atlas.views(for: "skeletal").compactMap(\.viewKey), ["skeletal-anterior", "skeletal-posterior"])
    XCTAssertEqual(atlas.views(for: "muscle").compactMap(\.viewKey), ["muscle-anterior", "muscle-posterior"])
    XCTAssertEqual(atlas.views(for: "scapula").compactMap(\.viewKey), ["skeletal-posterior"])
    XCTAssertEqual(atlas.views(for: "femur").compactMap(\.viewKey), ["skeletal-anterior"])
    XCTAssertEqual(atlas.views(for: "triceps-brachii").compactMap(\.viewKey), ["muscle-posterior"])
    XCTAssertEqual(atlas.plate(for: "femur", viewKey: "skeletal-posterior")?.viewKey, "skeletal-anterior")
    XCTAssertEqual(atlas.plate(for: "skeletal", viewKey: "invalid")?.viewKey, "skeletal-anterior")
    XCTAssertFalse(atlas.views(for: "cell-osteocyte").contains { $0.owner == "skeletal" })
    XCTAssertFalse(atlas.plate(for: "skeletal", viewKey: "skeletal-anterior")!.markers.contains { $0.id == "scapula" })
    XCTAssertFalse(atlas.plate(for: "muscle", viewKey: "muscle-posterior")!.markers.contains { $0.id == "quadriceps-femoris" })
  }

  func testPosteriorViewRestorationAndQuestionUseTheSelectedPlate() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let entry = try XCTUnwrap(atlas.entry("skeletal"))
    var selection = GalaxySSIHealthAtlasState.Selection()
    selection.artworkView = "skeletal-posterior"
    selection.zoom = 2
    let state = GalaxySSIHealthAtlasState()
    state.entries[entry.id] = selection
    let restored = GalaxySSIHealthAtlasState()
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.entries[entry.id]?.artworkView, "skeletal-posterior")
    XCTAssertEqual(restored.entries[entry.id]?.zoom, 2)
    let question = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selection, research: false, language: "en")
    XCTAssertTrue(question.contains(GalaxySSIHealthAtlasText.get("health_atlas_skeleton_back", "en")))
    XCTAssertFalse(question.contains(GalaxySSIHealthAtlasText.get("health_atlas_skeleton_front", "en")))
    selection.artworkView = "muscle-anterior"
    state.entries[entry.id] = selection
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertNil(restored.entries[entry.id]?.artworkView)
    XCTAssertEqual(restored.entries[entry.id]?.zoom, 2)
    let old = GalaxySSIHealthAtlasState.Selection()
    XCTAssertNil(try JSONDecoder().decode(GalaxySSIHealthAtlasState.Selection.self, from: JSONEncoder().encode(old)).artworkView)
  }

  func testMicroscopicValidationRejectsFallbackAndCrossOwnedFragments() throws {
    let base = try catalogue()
    XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(base, requireCompleteMicroscopic: true))
    let fragment = try XCTUnwrap(base.entry("fragment-platelet"))
    let model = GalaxySSIHealthAtlas.Mechanism(id: fragment.id, kind: "fragment", title: "Fragment title",
      stages: ["Adhere", "Activate", "Aggregate", "Support"], chapter: "18-5-hemostasis")
    let revised = base.entries.map { $0.id == fragment.id ? $0.replacing(mechanism: fragment.id) : $0 }
    let owned = GalaxySSIHealthAtlas(schema: base.schema, entries: revised, mechanisms: base.mechanisms + [model])
    XCTAssertNoThrow(try GalaxySSIHealthAtlas.validated(owned))
    let crossOwned = revised.map { $0.id == "heart" ? $0.replacing(mechanism: fragment.id) : $0 }
    XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: crossOwned, mechanisms: owned.mechanisms)))
    let wrongKind = GalaxySSIHealthAtlas.Mechanism(id: fragment.id, kind: "cell", title: model.title, stages: model.stages, chapter: model.chapter)
    XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(.init(schema: base.schema, entries: revised, mechanisms: base.mechanisms + [wrongKind])))
  }

  func testCompleteMicroscopicCatalogueRejectsInheritedProcessesAndSharedStageKeys() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let cells = atlas.entries.filter { $0.kind == .cell || $0.kind == .fragment }
    XCTAssertEqual(cells.filter { $0.kind == .cell }.count, 107)
    XCTAssertEqual(cells.filter { $0.kind == .fragment }.count, 1)
    XCTAssertEqual(atlas.mechanisms.filter { ["cell", "fragment"].contains($0.kind) }.count, 108)
    XCTAssertNoThrow(try GalaxySSIHealthAtlas.validated(atlas, requireCompleteMicroscopic: true))
    for entry in cells {
      XCTAssertEqual(entry.mechanism, entry.id)
      XCTAssertEqual(atlas.model(entry).kind, entry.kind.rawValue)
    }
    for id in ["cell-dendritic-cell", "fragment-platelet"] {
      let inherited = atlas.entries.map { $0.id == id ? $0.replacing(mechanism: "immune") : $0 }
      let missing = GalaxySSIHealthAtlas(schema: atlas.schema, entries: inherited, mechanisms: atlas.mechanisms.filter { $0.id != id })
      XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(missing, requireCompleteMicroscopic: true))
    }
    let first = atlas.model(cells[0]), second = atlas.model(cells[1])
    let duplicate = GalaxySSIHealthAtlas.Mechanism(id: first.id, kind: first.kind, title: second.title,
      stages: second.stages, chapter: first.chapter)
    let shared = GalaxySSIHealthAtlas(schema: atlas.schema, entries: atlas.entries,
      mechanisms: atlas.mechanisms.map { $0.id == first.id ? duplicate : $0 })
    XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(shared, requireCompleteMicroscopic: true))
  }

  func testSearchUsesAllWordsAndIncludesFragmentsOnlyInCellFilter() throws {
    let atlas = try catalogue()
    XCTAssertTrue(atlas.search("pancreatic beta", kind: .cell, system: "endocrine", language: "en")
      .contains { $0.id == "cell-pancreatic-beta-cell" })
    XCTAssertFalse(atlas.search("", kind: .organ, system: "", language: "en").contains { $0.kind == .cell })
    XCTAssertTrue(atlas.search("platelet", kind: .cell, system: "", language: "en").contains { $0.id == "fragment-platelet" })
    XCTAssertTrue(atlas.search("not-a-real-organ", kind: nil, system: "", language: "en").isEmpty)
  }

  func testLeaderRoutesAvoidOtherMarkersAndOmitAmbiguousTargets() {
    typealias Routes = GalaxySSIHealthAtlasLeaderRoutes
    let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 100, y: 0), obstacle = CGPoint(x: 50, y: 0)
    XCTAssertEqual(Routes.route(start: start, end: end, obstacles: [], clearance: 8), [start, end])
    let path = Routes.route(start: start, end: end, obstacles: [obstacle], clearance: 8)
    XCTAssertEqual(path.first, start); XCTAssertEqual(path.last, end)
    XCTAssertGreaterThan(path.count, 2)
    for (a, b) in zip(path, path.dropFirst()) {
      XCTAssertGreaterThanOrEqual(Routes.segmentDistance(obstacle, start: a, end: b), 8)
    }
    XCTAssertTrue(Routes.route(start: start, end: end, obstacles: [start], clearance: 8).isEmpty)
    XCTAssertTrue(Routes.route(start: start, end: end, obstacles: [], clearance: .nan).isEmpty)
    XCTAssertEqual(Routes.segmentDistance(CGPoint(x: 3, y: 4), start: start, end: start), 5)
  }

  func testOverviewPackPreservesDedicatedOrganRoutes() throws {
    let bundle = Bundle(for: GalaxySSIStore.self)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.OverviewPack.read(bundle: bundle))
    let atlas = try GalaxySSIHealthAtlas.load(bundle: bundle)
    XCTAssertEqual(pack.plates.count, 10)
    XCTAssertEqual(pack.plates.flatMap(\.markers).count, 53)
    XCTAssertEqual(pack.plates.flatMap(\.entryIDs).count, 54)
    XCTAssertNoThrow(try pack.validating(in: atlas, bundle: bundle))
    for owner in ["sensory", "respiratory", "digestive", "endocrine", "immune", "skin", "nervous", "cardio", "male", "female"] {
      XCTAssertEqual(atlas.plate(for: owner)?.owner, owner)
    }
    XCTAssertEqual(atlas.plate(for: "lungs")?.id, "lungs")
    XCTAssertEqual(atlas.plate(for: "liver")?.id, "liver")
    XCTAssertFalse(pack.plates.flatMap(\.entryIDs).contains("cell-neuron"))
    let categories = atlas.entries.filter { $0.kind == .system }
    XCTAssertEqual(categories.count, 14)
    for category in categories { XCTAssertNotNil(atlas.plate(for: category.id), category.id) }
    for id in ["spinal-cord", "spinal-nerves", "ganglia", "peripheral-nerves"] {
      XCTAssertEqual(atlas.plate(for: id)?.owner, "nervous")
    }
    for id in ["veins", "capillaries"] { XCTAssertEqual(atlas.plate(for: id)?.owner, "cardio") }
    XCTAssertEqual(atlas.plate(for: "brain")?.id, "brain")
    XCTAssertEqual(atlas.plate(for: "heart", viewKey: "heart-section")?.viewKey, "heart-section")
    XCTAssertEqual(atlas.plate(for: "aorta")?.id, "heart-section")
    XCTAssertEqual(atlas.plate(for: "mitral-valve")?.id, "heart-valves")
    let cardio = try XCTUnwrap(atlas.entry("cardio"))
    for id in ["aorta", "pulmonary-trunk", "lungs"] { XCTAssertTrue(atlas.children(cardio).contains { $0.id == id }) }
  }

  func testNervePreviewSeparatesAnatomyPlateAndQuantitativeSources() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let entry = try XCTUnwrap(atlas.entry("spinal-nerves"))
    var selection = GalaxySSIHealthAtlasState.Selection()
    selection.tab = .simulation; selection.physiologyInputs = [75, 30]
    for language in ["en", "zh-Hans"] {
      let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selection, research: false, language: language)
      XCTAssertTrue(prompt.contains("https://openstax.org/books/anatomy-and-physiology-2e/pages/12-4-the-action-potential"))
      XCTAssertTrue(prompt.contains("https://openstax.org/books/anatomy-and-physiology-2e/pages/12-1-basic-structure-and-function-of-the-nervous-system"))
      XCTAssertTrue(prompt.contains("https://www.ncbi.nlm.nih.gov/books/NBK10921/"))
      let model = try XCTUnwrap(GalaxySSIHealthAtlasPhysiology.restore(entry.id, inputs: [75, 30]))
      XCTAssertTrue(prompt.contains(GalaxySSIHealthAtlasPhysiologyText.result(model, language: language)))
    }
    XCTAssertEqual(GalaxySSIHealthAtlasPhysiology.Kind.forEntry("spinal-cord"), .potassium)
    XCTAssertEqual(GalaxySSIHealthAtlasPhysiology.Kind.forEntry("left-ventricle"), .ejection)
    XCTAssertEqual(GalaxySSIHealthAtlasPhysiology.Kind.forEntry("right-ventricle"), .ejection)
  }

  func testGermlineStageEndsSeparateMaternalPaternalAndCombinedCounts() throws {
    typealias Germline = GalaxySSIHealthAtlasGermline
    let fixtures: [(String, [Int], [Int])] = [
      ("cell-spermatogonium", [46, 46, 46, 46], [46, 46, 92, 92]),
      ("cell-spermatocyte", [46, 23, 23, 23], [92, 46, 23, 23]),
      ("cell-spermatozoon", [23, 23, 23, 23], [23, 23, 23, 23]),
      ("cell-oocyte-or-ovum", [23, 23, 23, 46], [46, 46, 23, 46])
    ]
    for (id, chromosomes, dna) in fixtures {
      for stage in 0..<4 {
        let counts = try XCTUnwrap(Germline.counts(id, stage: stage))
        XCTAssertEqual(counts.chromosomes, chromosomes[stage])
        XCTAssertEqual(counts.dnaMolecules, dna[stage])
        XCTAssertTrue(counts.dnaContent == counts.sets || counts.dnaContent == 2 * counts.sets)
      }
    }
    XCTAssertEqual(Germline.counts("cell-spermatozoon", stage: 3)?.target, .paternal)
    XCTAssertEqual(Germline.counts("cell-oocyte-or-ovum", stage: 2)?.target, .maternal)
    XCTAssertEqual(Germline.counts("cell-oocyte-or-ovum", stage: 3)?.target, .combined)
    XCTAssertNil(Germline.counts("cell-granulosa-cell", stage: 1))
    XCTAssertNil(Germline.counts("cell-spermatocyte", stage: 4))
    XCTAssertNil(Germline.counts("cell-spermatocyte", stage: -1))
    XCTAssertNil(Germline.Counts(sets: 3, dnaContent: 3, target: .cell))
    XCTAssertNil(Germline.Counts(sets: 1, dnaContent: 4, target: .cell))
  }

  func testReproductiveCatalogueAndSelectedGermlineStageRestoreTogether() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let base = try catalogue()
    XCTAssertTrue(Set(base.entries.map(\.id)).isSubset(of: Set(atlas.entries.map(\.id))))
    XCTAssertEqual(base.entries.count, 278); XCTAssertEqual(base.mechanisms.count, 20)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.ReproductivePack.read(bundle: Bundle(for: GalaxySSIStore.self)))
    let reproductiveIDs = Set(pack.mechanisms.map(\.id))
    XCTAssertEqual(atlas.mechanisms.filter { reproductiveIDs.contains($0.id) }.count, 15)
    for mechanism in pack.mechanisms where mechanism.kind == "cell" {
      XCTAssertEqual(atlas.entry(mechanism.id)?.kind, .cell)
      XCTAssertEqual(atlas.entry(mechanism.id)?.mechanism, mechanism.id)
      XCTAssertEqual(mechanism.stages.count, 4)
    }
    let id = "cell-oocyte-or-ovum", state = GalaxySSIHealthAtlasState()
    var selection = GalaxySSIHealthAtlasState.Selection()
    selection.tab = .simulation; selection.simulation.phase = 0.75
    state.entries[id] = selection
    let restored = GalaxySSIHealthAtlasState()
    restored.restore(state.serialized, atlas: atlas)
    let stage = try XCTUnwrap(restored.entries[id]?.simulation.stage)
    XCTAssertEqual(stage, 3)
    XCTAssertEqual(GalaxySSIHealthAtlasGermline.counts(id, stage: stage)?.target, .combined)
  }

  func testMetricAssociationsDoNotInventMissingOrganFunctionReadings() {
    XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry("heart"), [.bloodPressure, .restingHeartRate, .ldl, .hdl, .triglycerides])
    XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry("cell-pancreatic-beta-cell"), [.glucose, .hba1c])
    XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry("fragment-platelet"), [.platelets])
    XCTAssertTrue(GalaxySSIHealthAtlasMetrics.forEntry("brain").isEmpty)
    for id in ["urinary", "kidneys", "renal-cortex", "renal-medulla", "renal-pelvis", "nephron", "glomerulus",
      "renal-tubules", "collecting-ducts", "cell-podocyte", "bowmans-capsule", "proximal-tubule", "nephron-loop", "distal-tubule"] {
      XCTAssertEqual(GalaxySSIHealthAtlasMetrics.forEntry(id), [.creatinine, .urea, .urineProtein], id)
    }
    for id in ["cell-proximal-tubular-cell", "cell-distal-tubular-cell", "unknown"] {
      XCTAssertTrue(GalaxySSIHealthAtlasMetrics.forEntry(id).isEmpty, id)
    }
  }

  func testEarPackOwnsSixDistinctProcessesAndFiveAnatomyHotspots() throws {
    let bundle = Bundle(for: GalaxySSIStore.self), base = try catalogue()
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.EarPack.read(bundle: bundle))
    let atlas = try pack.applying(to: base, bundle: bundle)
    XCTAssertEqual(atlas.entries.count, base.entries.count)
    XCTAssertEqual(atlas.mechanisms.count, base.mechanisms.count + 6)
    for id in GalaxySSIHealthAtlasMiddleEar.ids {
      let entry = try XCTUnwrap(atlas.entry(id)), model = atlas.model(entry)
      XCTAssertEqual(entry.mechanism, id)
      XCTAssertEqual(model.id, id); XCTAssertEqual(model.kind, "organ"); XCTAssertEqual(model.stages.count, 4)
      XCTAssertEqual(atlas.plate(for: id)?.id, "ear")
    }
    let plate = GalaxySSIHealthAtlasMiddleEar.plate
    XCTAssertEqual(plate.markers.count, 5); XCTAssertEqual(plate.entryIDs.count, 6)
    XCTAssertEqual(plate.source, GalaxySSIHealthAtlasMiddleEar.anatomySource)
    XCTAssertThrowsError(try pack.applying(to: atlas, bundle: bundle))
    for language in ["en", "zh-Hans"] {
      for model in pack.mechanisms {
        for key in [model.title] + model.stages { XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(key, language), key) }
      }
    }
  }

  func testCellMechanismsMustBeOwnedByTheirCanonicalCell() throws {
    let base = try catalogue()
    let cell = GalaxySSIHealthAtlas.Mechanism(id: "cell-neuron", kind: "cell", title: "Cell process",
      stages: ["Receive", "Integrate", "Conduct", "Signal"], chapter: "12-2-nervous-tissue")
    func candidate(_ entries: [GalaxySSIHealthAtlas.Entry]) -> GalaxySSIHealthAtlas {
      .init(schema: 1, entries: entries, mechanisms: base.mechanisms + [cell])
    }
    XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(candidate(base.entries)))
    let owned = base.entries.map { $0.id == cell.id ? $0.replacing(mechanism: cell.id) : $0 }
    XCTAssertNoThrow(try GalaxySSIHealthAtlas.validated(candidate(owned)))
    for foreign in ["cell-erythrocyte", "heart"] {
      let misplaced = owned.map { $0.id == foreign ? $0.replacing(mechanism: cell.id) : $0 }
      XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(candidate(misplaced)))
    }
  }

  func testStageSelectionOnlyChangesPhaseAndRestoresWithoutChangingInputs() throws {
    var simulation = GalaxySSIHealthAtlasSimulation(first: 100, second: 60, phase: 0.8, speed: 2)
    for index in 0..<4 {
      XCTAssertTrue(simulation.selectStage(index))
      XCTAssertEqual(simulation.stage, index)
      XCTAssertEqual(simulation.phase, Double(index) / 4)
      XCTAssertEqual(simulation.first, 100); XCTAssertEqual(simulation.second, 60); XCTAssertEqual(simulation.speed, 2)
      let restored = try JSONDecoder().decode(GalaxySSIHealthAtlasSimulation.self, from: JSONEncoder().encode(simulation))
      XCTAssertEqual(restored, simulation)
    }
    let saved = simulation
    XCTAssertFalse(simulation.selectStage(-1)); XCTAssertFalse(simulation.selectStage(4))
    XCTAssertEqual(simulation, saved)
  }

  func testBundledArtworkPackIsAdditiveAndValidatesCoordinates() throws {
    let atlas = try catalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let extra = GalaxySSIHealthAtlas.Entry(id: "test-structure", kind: .organ, name: "name", description: "description",
      systems: ["urinary"], related: ["nephron"], mechanism: "urinary", aliases: "aliases", color: "", icon: "")
    func pack(x: Double = 0.5, anchor: String = "kidneys") -> GalaxySSIHealthAtlas.ArtworkPack {
      .init(schema: 1, entries: [extra], insertAfter: [extra.id: anchor], relatedAdditions: ["kidneys": [extra.id]],
        plates: [.init(id: "test", asset: "HealthAtlasBody", owner: "kidneys", viewLabel: "health_atlas_illustration",
          entryIDs: [extra.id], aspectRatio: 2.0 / 3.0, markers: [.init(id: extra.id, x: x, y: 0.5)])], english: [:])
    }
    let merged = try pack().applying(to: atlas, bundle: bundle)
    XCTAssertEqual(merged.entries.count, atlas.entries.count + 1)
    XCTAssertEqual(merged.entry("kidneys")?.related.first, extra.id)
    let index = try XCTUnwrap(merged.entries.firstIndex { $0.id == "kidneys" })
    XCTAssertEqual(merged.entries[index + 1].id, extra.id)
    XCTAssertThrowsError(try pack(x: .nan).applying(to: atlas, bundle: bundle))
    XCTAssertThrowsError(try pack(x: 1.1).applying(to: atlas, bundle: bundle))
    XCTAssertThrowsError(try pack(anchor: "missing").applying(to: atlas, bundle: bundle))
    XCTAssertThrowsError(try pack().applying(to: merged, bundle: bundle))
  }

  func testSystemPlatesRequireVisibleMacroscopicTargetsAndTrustedReferences() throws {
    let atlas = try catalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    func pack(target: String = "ureters", source: String = "https://openstax.org/books/anatomy") -> GalaxySSIHealthAtlas.SystemPack {
      .init(schema: 1, plates: [.init(id: "urinary", asset: "HealthAtlasBody", owner: "urinary",
        viewLabel: "health_atlas_view_urinary", entryIDs: ["urinary", target], aspectRatio: 2.0 / 3.0,
        markers: [.init(id: target, x: 0.5, y: 0.5)], source: URL(string: source))],
        english: ["health_atlas_view_urinary": "Urinary schematic"])
    }
    XCTAssertNoThrow(try pack().applying(to: atlas, bundle: bundle))
    for target in ["cell-pancreatic-beta-cell", "fragment-platelet", "missing"] {
      XCTAssertThrowsError(try pack(target: target).applying(to: atlas, bundle: bundle))
    }
    for source in ["http://openstax.org/books", "https://example.com/books", "https://user@openstax.org/books"] {
      XCTAssertThrowsError(try pack(source: source).applying(to: atlas, bundle: bundle))
    }
    let legacy = Data(#"{"id":"old","asset":"HealthAtlasBody","viewLabel":"health_atlas_illustration","entryIDs":[""],"aspectRatio":1,"markers":[]}"#.utf8)
    XCTAssertNil(try JSONDecoder().decode(GalaxySSIHealthAtlas.Plate.self, from: legacy).source)
  }

  func testTeachingEquationsAndDefensiveRestoration() {
    var heart = GalaxySSIHealthAtlasSimulation.initial("heart")
    XCTAssertEqual(heart.output, 4.9, accuracy: 0.0001)
    let lung = GalaxySSIHealthAtlasSimulation.initial("lungs")
    XCTAssertEqual(lung.output, 6, accuracy: 0.0001)
    heart.phase = .nan; heart.speed = .infinity; heart.first = -10; heart.second = 1_000
    heart.sanitize("heart")
    XCTAssertEqual(heart.phase, 0); XCTAssertEqual(heart.speed, 1)
    XCTAssertEqual(heart.first, 40); XCTAssertEqual(heart.second, 120)
    heart.phase = 1; XCTAssertEqual(heart.stage, 3)
    var elimination = GalaxySSIHealthAtlasElimination()
    XCTAssertEqual(elimination.percent(at: 0), 100)
    XCTAssertEqual(elimination.percent(at: 8), 25, accuracy: 0.0001)
    elimination.halfLife = .nan; elimination.elapsed = 90; elimination.sanitize()
    XCTAssertEqual(elimination.halfLife, 4); XCTAssertEqual(elimination.elapsed, 48)
  }

  func testHeartSectionViewsAndValveStatesMatchAndroidOwnershipAndPhases() throws {
    typealias Heart = GalaxySSIHealthAtlasHeartSection
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.HeartSectionPack.read(bundle: Bundle(for: GalaxySSIStore.self)))
    XCTAssertEqual(pack.entries.count, 17); XCTAssertEqual(pack.mechanisms.count, 11)
    for model in pack.mechanisms {
      let entry = try XCTUnwrap(atlas.entry(model.id))
      XCTAssertEqual(entry.mechanism, model.id); XCTAssertEqual(atlas.model(entry).stages.count, 4)
    }
    XCTAssertEqual(atlas.views(for: "heart").map(\.viewKey), ["heart-exterior", "heart-section"])
    XCTAssertEqual(Heart.section.markers.count, 6); XCTAssertEqual(Heart.valves.markers.count, 4)
    for id in ["left-atrium", "right-atrium", "left-ventricle", "right-ventricle"] {
      let chamber = try XCTUnwrap(atlas.entry(id))
      XCTAssertTrue(atlas.tissues(chamber).contains { $0.id == "tissue-cardiac-muscle" })
      XCTAssertTrue(atlas.cells(chamber).contains { $0.id == "cell-cardiomyocyte" })
    }
    for id in ["aorta", "pulmonary-trunk"] {
      XCTAssertTrue(atlas.tissues(try XCTUnwrap(atlas.entry(id))).contains { $0.id == "tissue-vascular-endothelium" })
    }
    XCTAssertEqual(atlas.plate(for: "heart", viewKey: "heart-section")?.id, "heart-section")
    XCTAssertEqual(atlas.plate(for: "heart", viewKey: "unknown")?.id, "heart-exterior")
    let expected: [Set<String>] = [["tricuspid-valve", "mitral-valve"], [], ["pulmonary-valve", "aortic-valve"], []]
    for stage in 0..<4 {
      XCTAssertEqual(Set(Heart.Valve.allCases.filter { $0.openAt(stage) == true }.map(\.id)), expected[stage])
      for valve in Heart.Valve.allCases {
        XCTAssertEqual(atlas.plate(for: valve.id)?.id, "heart-valves")
        XCTAssertFalse(GalaxySSIHealthAtlasCirculation.supports(valve.id))
      }
    }
    for valve in Heart.Valve.allCases {
      XCTAssertNil(valve.openAt(-1)); XCTAssertNil(valve.openAt(4))
    }
    XCTAssertFalse(GalaxySSIHealthAtlasCirculation.supports("heart-valves"))
    for language in ["en", "zh-Hans"] {
      let context = try XCTUnwrap(Heart.context("mitral-valve", stage: 2, atlas: atlas, language: language))
      XCTAssertTrue(context.contains(try XCTUnwrap(Heart.label(.mitral, stage: 2, atlas: atlas, language: language))))
      XCTAssertFalse(context.contains(try XCTUnwrap(Heart.label(.aortic, stage: 2, atlas: atlas, language: language))))
      XCTAssertTrue(context.contains(Heart.cycleSource.absoluteString))
    }
  }

  func testPaintedCardiacSectionSharesNormalizedLeafletAnchors() throws {
    typealias Heart = GalaxySSIHealthAtlasHeartSection
    XCTAssertEqual(Heart.section.aspectRatio, 1); XCTAssertEqual(Heart.valves.aspectRatio, 1)
    let expected: [(String, Double, Double)] = [("tricuspid-valve",451,707),("mitral-valve",859,659),
      ("pulmonary-valve",599,603),("aortic-valve",708,589)]
    for (valve, value) in zip(Heart.Valve.allCases, expected) {
      let marker = try XCTUnwrap(Heart.valves.markers.first { $0.id == valve.id })
      XCTAssertEqual(marker.id, value.0)
      XCTAssertEqual(marker.x, value.1 / 1254, accuracy: 0.000001)
      XCTAssertEqual(marker.y, value.2 / 1254, accuracy: 0.000001)
      XCTAssertEqual(marker.x, valve.marker.x); XCTAssertEqual(marker.y, valve.marker.y)
    }
  }

  func testHeartArtworkAndIndependentEjectionSelectionsRestorePerEntry() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let state = GalaxySSIHealthAtlasState(), restored = GalaxySSIHealthAtlasState()
    var heart = GalaxySSIHealthAtlasState.Selection()
    heart.artworkView = "heart-section"; state.entries["heart"] = heart
    var left = GalaxySSIHealthAtlasState.Selection()
    left.physiologyInputs = [90, 60]; state.entries["left-ventricle"] = left
    var right = GalaxySSIHealthAtlasState.Selection()
    right.physiologyInputs = [70, 80]; state.entries["right-ventricle"] = right
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.entries["heart"]?.artworkView, "heart-section")
    XCTAssertEqual(restored.entries["left-ventricle"]?.physiologyInputs, [90, 60])
    XCTAssertEqual(restored.entries["right-ventricle"]?.physiologyInputs, [70, 80])
  }

  func testDedicatedEyePlateOverridesOverviewAndUsesExactTrustedSource() throws {
    let atlas = try catalogue()
    for id in ["eye", "cornea", "lens", "retina"] {
      let plate = try XCTUnwrap(atlas.plate(for: id))
      XCTAssertEqual(plate.id, "eye")
      XCTAssertEqual(plate.owner, "eye")
      XCTAssertEqual(plate.asset, "HealthAtlasEyeSection")
      XCTAssertEqual(plate.markers.map(\.id), ["cornea", "lens", "retina"])
      XCTAssertEqual(plate.source, GalaxySSIHealthAtlasEyeOptics.anatomySource)
      XCTAssertNotNil(UIImage(named: plate.asset, in: Bundle(for: GalaxySSIStore.self), compatibleWith: nil))
    }
    XCTAssertNotEqual(atlas.plate(for: "sensory")?.id, "eye")
    XCTAssertNotEqual(atlas.plate(for: "cell-rod-photoreceptor")?.id, "eye")
    XCTAssertTrue(GalaxySSIHealthAtlas.trustedPlateSource(GalaxySSIHealthAtlasEyeOptics.anatomySource))
    for source in ["http://www.nei.nih.gov/eye-health-information/healthy-vision/nei-for-kids/about-eye",
      "https://www.nei.nih.gov/other", "https://user@www.nei.nih.gov/eye-health-information/healthy-vision/nei-for-kids/about-eye"] {
      XCTAssertFalse(GalaxySSIHealthAtlas.trustedPlateSource(URL(string: source)))
    }
  }

  func testCalendarMonthYearWindowsAcrossLeapDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 31, hour: 12)))
    XCTAssertEqual(GalaxySSIHealthAtlasWindow.week.days(through: date, calendar: calendar), 7)
    XCTAssertEqual(GalaxySSIHealthAtlasWindow.month.days(through: date, calendar: calendar), 31)
    XCTAssertEqual(GalaxySSIHealthAtlasWindow.year.days(through: date, calendar: calendar), 366)
  }

  func testPublicSelectionRoundTripAndUnknownIDsCannotGrowState() throws {
    let atlas = try catalogue(), first = GalaxySSIHealthAtlasState()
    let heart = try XCTUnwrap(atlas.entry("heart"))
    first.binding(heart).wrappedValue.tab = .simulation
    first.binding(heart).wrappedValue.simulation.phase = 0.5
    let restored = GalaxySSIHealthAtlasState()
    restored.restore(first.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(heart).wrappedValue.tab, .simulation)
    XCTAssertEqual(restored.binding(heart).wrappedValue.simulation.phase, 0.5)
    XCTAssertFalse(first.serialized.contains("measuredAt"))
    restored.restore(String(repeating: "x", count: 256_001), atlas: atlas)
    XCTAssertEqual(restored.entries.count, 1)
  }

  func testTissueCatalogueHasExplicitLocationsExamplesAndIndependentMechanisms() throws {
    let bundle = Bundle(for: GalaxySSIStore.self)
    let atlas = try GalaxySSIHealthAtlas.load(bundle: bundle)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.TissuePack.read(bundle: bundle))
    let tissues = atlas.entries.filter { $0.kind == .tissue }
    XCTAssertEqual(tissues.count, 14); XCTAssertEqual(pack.mechanisms.count, 14)
    XCTAssertEqual(Set(pack.entries.flatMap(\.locations)).count, 53)
    XCTAssertEqual(Set(tissues.flatMap(\.related)).count, 26)
    XCTAssertEqual(pack.plates.count, 14); XCTAssertEqual(pack.plates.flatMap(\.markers).count, 17)
    for tissue in tissues {
      XCTAssertEqual(tissue.mechanism, tissue.id); XCTAssertEqual(atlas.model(tissue).kind, "tissue")
      XCTAssertEqual(atlas.cells(tissue).map(\.id), tissue.related)
      XCTAssertEqual(atlas.plate(for: tissue.id)?.owner, tissue.id)
      for location in tissue.locations {
        let organ = try XCTUnwrap(atlas.entry(location))
        XCTAssertEqual(organ.kind, .organ)
        XCTAssertTrue(atlas.tissues(organ).contains { $0.id == tissue.id })
        XCTAssertTrue(atlas.parents(tissue).contains { $0.id == organ.id })
      }
      for language in ["en", "zh-Hans"] {
        let name = GalaxySSIHealthAtlasText.get(tissue.name, language)
        XCTAssertTrue(atlas.search(name, kind: .tissue, system: "", language: language).contains { $0.id == tissue.id })
        for key in [tissue.name, tissue.description, tissue.aliases, atlas.model(tissue).title] + atlas.model(tissue).stages {
          XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(key, language), key)
        }
      }
      XCTAssertTrue(GalaxySSIHealthAtlasMetrics.forEntry(tissue.id).isEmpty)
    }
    XCTAssertThrowsError(try pack.applying(to: atlas, bundle: bundle))
  }

  func testTissueGraphRejectsInvalidLocationsExamplesAndBorrowedMechanisms() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let cardiac = try XCTUnwrap(atlas.entry("tissue-cardiac-muscle"))
    func reject(_ replacement: GalaxySSIHealthAtlas.Entry) {
      let revised = atlas.entries.map { $0.id == replacement.id ? replacement : $0 }
      XCTAssertThrowsError(try GalaxySSIHealthAtlas.validated(.init(schema: atlas.schema, entries: revised, mechanisms: atlas.mechanisms)))
    }
    for locations in [[], ["heart", "heart"], ["missing"], ["cell-cardiomyocyte"], ["skin-organ"]] {
      var invalid = cardiac; invalid.locatedIn = locations; reject(invalid)
    }
    reject(cardiac.replacing(related: ["ventricles"]))
    reject(cardiac.replacing(related: []))
    reject(cardiac.replacing(mechanism: "tissue-skeletal-muscle"))
    var heart = try XCTUnwrap(atlas.entry("heart")); heart.locatedIn = ["heart"]; reject(heart)
    reject(try XCTUnwrap(atlas.entry("heart")).replacing(mechanism: cardiac.id))
    let legacy = try catalogue()
    XCTAssertTrue(legacy.entries.allSatisfy { $0.locations.isEmpty })
  }

  func testOrganStructureLayerRestoresIndependentlyAndTissuePreviewStaysPublic() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let state = GalaxySSIHealthAtlasState(), restored = GalaxySSIHealthAtlasState()
    let heart = try XCTUnwrap(atlas.entry("heart")), lung = try XCTUnwrap(atlas.entry("lungs"))
    state.binding(heart).wrappedValue.selectedStructureLayer = .tissue
    state.binding(lung).wrappedValue.selectedStructureLayer = .cell
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(heart).wrappedValue.selectedStructureLayer, .tissue)
    XCTAssertEqual(restored.binding(lung).wrappedValue.selectedStructureLayer, .cell)
    state.binding(heart).wrappedValue.structureLayer = "unknown"
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(heart).wrappedValue.selectedStructureLayer, .organ)
    let tissue = try XCTUnwrap(atlas.entry("tissue-cardiac-muscle"))
    var selection = GalaxySSIHealthAtlasState.Selection()
    selection.tab = .simulation; selection.simulation.phase = 0.5
    for language in ["en", "zh-Hans"] {
      let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: tissue, selection: selection, research: false, language: language)
      for line in atlas.tissueContext(tissue, language: language) { XCTAssertTrue(prompt.contains(line)) }
      XCTAssertTrue(prompt.contains(GalaxySSIHealthAtlasText.get(atlas.model(tissue).stages[2], language)))
      XCTAssertFalse(prompt.contains("measuredAt"))
      XCTAssertFalse(prompt.contains("tissue_epidermal"))
      var values = selection; values.tab = .values
      XCTAssertEqual(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: tissue, selection: values,
        research: false, language: language), "")
    }
  }

  func testAgingTopicsLocalizeStagesAndKeepIndependentRestorableState() throws {
    typealias Topic = GalaxySSIHealthAtlasAgingTopic
    typealias Aging = GalaxySSIHealthAtlasAgingSelection
    let atlas = try catalogue(), state = GalaxySSIHealthAtlasState()
    XCTAssertEqual(Topic.allCases.count, 12)
    XCTAssertEqual(Topic.allCases.filter { $0.study != nil }, [.telomeres, .senescence])
    XCTAssertEqual(Topic.forEntry("heart"), .mitochondria)
    XCTAssertEqual(Topic.forEntry("skin-organ"), .telomeres)
    XCTAssertEqual(Topic.forEntry("cell-t-cell"), .senescence)
    XCTAssertEqual(Topic.forEntry("colon"), .dysbiosis)
    XCTAssertEqual(Topic.forEntry("unknown"), .genome)
    for topic in Topic.allCases {
      XCTAssertNotNil(atlas.entry(topic.exampleID))
      XCTAssertNil(Aging(topic: topic, step: -1))
      XCTAssertNil(Aging(topic: topic, step: 4))
      for step in 0..<4 {
        let selected = try XCTUnwrap(Aging(topic: topic, step: step))
        XCTAssertEqual(try JSONDecoder().decode(Aging.self, from: JSONEncoder().encode(selected)), selected)
        for language in ["en", "zh-Hans"] {
          XCTAssertEqual(selected.stages(language: language).count, 4)
          XCTAssertFalse(selected.context(language: language).contains("health_atlas_"))
          XCTAssertTrue(selected.context(language: language).contains(selected.stages(language: language)[step]))
        }
      }
    }
    let heart = try XCTUnwrap(atlas.entry("heart")), skin = try XCTUnwrap(atlas.entry("skin-organ"))
    state.binding(heart).wrappedValue.aging = Aging(topic: .senescence, step: 3)
    state.binding(skin).wrappedValue.aging = Aging(topic: .telomeres, step: 1)
    state.binding(heart).wrappedValue.tab = .simulation
    let next = GalaxySSIHealthAtlasState()
    next.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(next.binding(heart).wrappedValue.aging, Aging(topic: .senescence, step: 3))
    XCTAssertEqual(next.binding(skin).wrappedValue.aging, Aging(topic: .telomeres, step: 1))
    let legacy = GalaxySSIHealthAtlasState.Selection()
    XCTAssertNil(legacy.aging)
    XCTAssertEqual(Aging.resolved(legacy.aging, entryID: heart.id).topic, .mitochondria)
    let malformed = try JSONDecoder().decode(Aging.self, from: Data(#"{"topic":"telomeres","step":99}"#.utf8))
    XCTAssertEqual(Aging.resolved(malformed, entryID: "heart"), Aging(topic: .mitochondria))
  }

  func testImmuneFeaturesAreLocalExplanationsAndLegacyMarkersStillNavigate() throws {
    let bundle = Bundle(for: GalaxySSIStore.self), atlas = try completeCatalogue()
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.ImmunePack.read(bundle: bundle))
    try pack.validating(in: atlas, bundle: bundle)
    XCTAssertEqual(pack.plates.count, 12)
    XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 25)
    for plate in pack.plates {
      for feature in plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature(let selected) = plate.labelTarget(feature.id, in: atlas) else {
          return XCTFail("Local annotation must open an explanation")
        }
        XCTAssertEqual(selected.id, feature.id)
        for language in ["en", "zh-Hans"] {
          XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(feature.explanation, language), feature.explanation)
          XCTAssertTrue(try XCTUnwrap(plate.featureContext(language: language)).contains(
            GalaxySSIHealthAtlasText.get(feature.title, language)))
        }
      }
      XCTAssertNil(plate.labelTarget("heart", in: atlas))
      XCTAssertNil(plate.labelTarget("unknown", in: atlas))
    }
    let legacy: [String: Any] = ["id": "legacy", "asset": "legacy", "viewLabel": "legacy",
      "entryIDs": ["heart"], "aspectRatio": 1, "markers": [["id": "heart", "x": 0.5, "y": 0.5]]]
    func decode(_ object: [String: Any]) throws -> GalaxySSIHealthAtlas.Plate {
      try JSONDecoder().decode(GalaxySSIHealthAtlas.Plate.self, from: JSONSerialization.data(withJSONObject: object))
    }
    let old = try decode(legacy)
    XCTAssertNil(old.features)
    XCTAssertNil(old.featureContext(language: "en"))
    guard case .anatomy("heart") = old.labelTarget("heart", in: atlas) else { return XCTFail("Legacy route lost") }
    var duplicate = legacy
    duplicate["features"] = [["marker": ["id": "heart", "x": 0.5, "y": 0.5],
      "title": "local", "explanation": "local_detail"]]
    XCTAssertThrowsError(try decode(duplicate))
    var outside = legacy
    outside["markers"] = [["id": "heart", "x": 1.1, "y": 0.5]]
    XCTAssertThrowsError(try decode(outside))
    let owner = try XCTUnwrap(atlas.entry(GalaxySSIHealthAtlas.ImmunePack.phagocytosisOwner))
    let stages = atlas.model(owner).stages
    for stage in 0..<4 {
      XCTAssertNotNil(GalaxySSIHealthAtlasPhagocytosis.label(stage: stage, stages: stages, language: "en"))
    }
    XCTAssertNil(GalaxySSIHealthAtlasPhagocytosis.label(stage: 4, stages: stages, language: "en"))
  }

  func testPhagocytosisFollowsSharedPhaseWithinEachStageAndRewindsExactly() throws {
    typealias Frame = GalaxySSIHealthAtlasPhagocytosis.Frame
    for stage in 0..<4 {
      let start = try XCTUnwrap(Frame(Double(stage) / 4 + 0.02))
      let later = try XCTUnwrap(Frame(Double(stage) / 4 + 0.15))
      XCTAssertEqual(start.stage, stage); XCTAssertEqual(later.stage, stage)
      XCTAssertGreaterThan(later.ease, start.ease)
      XCTAssertEqual(start, Frame(Double(stage) / 4 + 0.02))
      switch stage {
      case 0: XCTAssertLessThan(later.particleX, start.particleX)
      case 1:
        XCTAssertLessThan(later.particleX, start.particleX)
        XCTAssertGreaterThan(later.compartmentRadius, start.compartmentRadius)
        XCTAssertGreaterThan(later.compartmentOpacity, start.compartmentOpacity)
      case 2:
        for (before, after) in zip(start.fragmentRadii, later.fragmentRadii) { XCTAssertLessThan(after, before) }
      default: XCTAssertGreaterThan(later.signalDrift, start.signalDrift)
      }
    }
    let halfway = try XCTUnwrap(Frame(0.125))
    XCTAssertEqual(halfway.ease, 0.5, accuracy: 0.000001)
    XCTAssertEqual(halfway.particleX, 258, accuracy: 0.000001)
    let end = try XCTUnwrap(Frame(1))
    XCTAssertEqual(end.stage, 3); XCTAssertEqual(end.signalDrift, 18)
    XCTAssertEqual(Frame(-1), Frame(0)); XCTAssertEqual(Frame(2), Frame(1))
    XCTAssertNil(Frame(.nan)); XCTAssertNil(Frame(.infinity))
    var simulation = GalaxySSIHealthAtlasSimulation.initial("cell-macrophage")
    for stage in 0..<4 {
      XCTAssertTrue(simulation.selectStage(stage))
      XCTAssertEqual(Frame(simulation.phase)?.stage, simulation.stage)
    }
    simulation.phase = 0.39
    let saved = try JSONEncoder().encode(simulation)
    let restored = try JSONDecoder().decode(GalaxySSIHealthAtlasSimulation.self, from: saved)
    XCTAssertEqual(Frame(restored.phase), Frame(simulation.phase))
  }

  func testGranulocyteLessonsHaveIndependentGeometryAndDeterministicFrames() throws {
    typealias Lesson = GalaxySSIHealthAtlasGranulocyte
    typealias Frame = Lesson.Frame
    let atlas = try completeCatalogue()
    XCTAssertEqual(Lesson.allCases.count, 3); XCTAssertNil(Lesson(rawValue: "cell-macrophage"))
    for lesson in Lesson.allCases {
      let entry = try XCTUnwrap(atlas.entry(lesson.rawValue))
      let plate = try XCTUnwrap(atlas.plate(for: entry.id))
      XCTAssertEqual(plate.asset, lesson.asset); XCTAssertEqual(plate.aspectRatio, 1)
      for language in ["en", "zh-Hans"] {
        XCTAssertNotEqual(GalaxySSIHealthAtlasText.get("health_atlas_" + lesson.scopeKey, language), "health_atlas_" + lesson.scopeKey)
        for stage in 0..<4 {
          XCTAssertNotNil(Lesson.label(stage: stage, stages: atlas.model(entry).stages, language: language))
          let phase = Double(stage) / 4 + 0.1
          let frame = try XCTUnwrap(Frame(lesson, phase: phase))
          XCTAssertEqual(frame.stage, stage); XCTAssertEqual(frame, Frame(lesson, phase: phase))
          XCTAssertEqual(frame.ease, 0.352, accuracy: 0.000001)
          XCTAssertGreaterThan(frame.cellBounds.width, 0); XCTAssertGreaterThan(frame.cellBounds.height, 0)
        }
      }
      XCTAssertNil(Lesson.label(stage: 4, stages: atlas.model(entry).stages, language: "en"))
      XCTAssertNil(Lesson.label(stage: 0, stages: [], language: "en"))
      XCTAssertNil(Frame(lesson, phase: .nan)); XCTAssertNil(Frame(lesson, phase: .infinity))
      XCTAssertEqual(Frame(lesson, phase: -1), Frame(lesson, phase: 0))
      XCTAssertEqual(Frame(lesson, phase: 2), Frame(lesson, phase: 1))
    }
    let migration = try XCTUnwrap(Frame(.neutrophil, phase: 0.125))
    XCTAssertEqual(migration.cellBounds.midX, 130.5, accuracy: 0.000001)
    let exit = try XCTUnwrap(Frame(.neutrophil, phase: 0.375))
    XCTAssertEqual(exit.cellBounds.midY, 96.5, accuracy: 0.000001)
    XCTAssertEqual(exit.cellBounds.width, 126 * 0.725, accuracy: 0.000001)
    let uptake = try XCTUnwrap(Frame(.neutrophil, phase: 0.625))
    XCTAssertEqual(uptake.uptakeX, 243); XCTAssertEqual(uptake.uptakeRadius, 13.5)
    let contact = try XCTUnwrap(Frame(.eosinophil, phase: 0.375))
    XCTAssertEqual(contact.cellBounds.midX, 159.5, accuracy: 0.000001)
    let response = try XCTUnwrap(Frame(.basophil, phase: 1))
    XCTAssertEqual(response.vesselResponse, 9); XCTAssertEqual(response.cellBounds.midX, 110)
  }

  func testTransportCellPlatesKeepLocalFeaturesAndExplicitSubtypeCaptions() throws {
    let bundle = Bundle(for: GalaxySSIStore.self), atlas = try completeCatalogue()
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.TransportCellPack.read(bundle: bundle))
    try pack.validating(in: atlas, bundle: bundle)
    XCTAssertEqual(pack.plates.count, 12)
    XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 25)
    for plate in pack.plates {
      let owner = try XCTUnwrap(plate.owner)
      XCTAssertEqual(atlas.plate(for: owner)?.asset, plate.asset)
      XCTAssertEqual(atlas.entry(owner)?.kind, .cell)
      for feature in plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature(let selected) = plate.labelTarget(feature.id, in: atlas) else { return XCTFail("Feature must explain locally") }
        XCTAssertEqual(selected.id, feature.id)
        for language in ["en", "zh-Hans"] {
          XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(feature.explanation, language), feature.explanation)
        }
      }
    }
    XCTAssertEqual(atlas.plate(for: "cell-collecting-duct-intercalated-cell")?.viewLabel, "health_atlas_type_a_intercalated_view")
    XCTAssertEqual(atlas.plate(for: "cell-urothelial-cell")?.viewLabel, "health_atlas_umbrella_view")
    let podocyte = try XCTUnwrap(atlas.entry(GalaxySSIHealthAtlasFiltrationStage.owner))
    let typeII = try XCTUnwrap(atlas.entry("cell-type-ii-pneumocyte"))
    let state = GalaxySSIHealthAtlasState(), restored = GalaxySSIHealthAtlasState()
    state.binding(podocyte).wrappedValue.simulation.selectStage(3)
    state.binding(typeII).wrappedValue.physiologyInputs = [30, 200]
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(podocyte).wrappedValue.simulation.stage, 3)
    XCTAssertEqual(restored.binding(typeII).wrappedValue.physiologyInputs, [30, 200])
    for language in ["en", "zh-Hans"] {
      var selection = state.binding(podocyte).wrappedValue; selection.tab = .simulation
      let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: podocyte, selection: selection,
        research: false, language: language)
      XCTAssertTrue(prompt.contains(GalaxySSIHealthAtlasText.get("health_atlas_podocyte_scope", language)))
      selection.tab = .values
      XCTAssertEqual(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: podocyte, selection: selection,
        research: false, language: language), "")
    }
  }

  func testCoreCellsUseDedicatedAnnotatedPlatesWithoutChangingCatalogueIdentity() throws {
    let bundle = Bundle(for: GalaxySSIStore.self), atlas = try completeCatalogue()
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.CoreCellPack.read(bundle: bundle))
    try pack.validating(in: atlas, bundle: bundle)
    XCTAssertEqual(pack.plates.count, 18)
    XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 39)
    let immune = try XCTUnwrap(GalaxySSIHealthAtlas.ImmunePack.read(bundle: bundle))
    let combined = pack.plates + immune.plates
    XCTAssertEqual(Set(combined.compactMap(\.owner)).count, 30)
    for plate in combined {
      let owner = try XCTUnwrap(plate.owner)
      XCTAssertEqual(atlas.plate(for: owner)?.asset, plate.asset)
      for feature in plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature(let selected) = plate.labelTarget(feature.id, in: atlas) else {
          return XCTFail("Core cell feature navigated out of its illustration")
        }
        XCTAssertEqual(selected.id, feature.id)
      }
    }
    let cell = try XCTUnwrap(atlas.entry(GalaxySSIHealthAtlasSarcomere.owner))
    let state = GalaxySSIHealthAtlasState(), restored = GalaxySSIHealthAtlasState()
    state.binding(cell).wrappedValue.tab = .simulation
    state.binding(cell).wrappedValue.simulation.selectStage(2)
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(cell).wrappedValue.simulation.stage, 2)
    for language in ["en", "zh-Hans"] {
      let selection = state.binding(cell).wrappedValue
      let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: cell, selection: selection,
        research: false, language: language)
      let model = try XCTUnwrap(GalaxySSIHealthAtlasSarcomere(stage: 2))
      for line in model.context(text: { GalaxySSIHealthAtlasText.get("health_atlas_" + $0, language) }) {
        XCTAssertTrue(prompt.contains(line))
      }
      var structure = selection; structure.tab = .structure
      let publicStructure = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: cell, selection: structure,
        research: false, language: language)
      XCTAssertFalse(publicStructure.contains(GalaxySSIHealthAtlasText.get("health_atlas_sarcomere_scope", language)))
    }
  }

  func testDigestivePlatesAndSeparatePancreaticMechanismsPreserveCellIdentity() throws {
    let atlas = try completeCatalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.DigestivePack.read(bundle: bundle))
    XCTAssertEqual(pack.plates.count, 14)
    XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 27)
    XCTAssertEqual(pack.plates.flatMap(\.markers).count, 4)
    for plate in pack.plates {
      let owner = try XCTUnwrap(plate.owner)
      XCTAssertEqual(atlas.plate(for: owner)?.asset, plate.asset)
      XCTAssertTrue(GalaxySSIHealthAtlas.trustedPlateSource(plate.source))
      for feature in plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature = plate.labelTarget(feature.id, in: atlas) else { return XCTFail("Expected local explanation") }
      }
      for marker in plate.markers {
        guard case .anatomy(let id) = plate.labelTarget(marker.id, in: atlas) else { return XCTFail("Expected cell navigation") }
        XCTAssertEqual(atlas.entry(id)?.kind, .cell)
      }
    }
    for id in ["pancreas", "pancreatic-islets"] {
      let entry = try XCTUnwrap(atlas.entry(id))
      XCTAssertEqual(entry.mechanism, id); XCTAssertEqual(atlas.model(entry).kind, "secretion")
      XCTAssertEqual(atlas.model(entry).stages.count, 4)
    }
    for id in GalaxySSIHealthAtlasPancreatic.isletCells {
      XCTAssertEqual(atlas.entry(id)?.mechanism, id)
      XCTAssertNotNil(atlas.plate(for: id))
    }
    let pancreas = try XCTUnwrap(atlas.entry("pancreas")), state = GalaxySSIHealthAtlasState()
    state.binding(pancreas).wrappedValue.physiologyInputs = [40, 120]
    state.binding(pancreas).wrappedValue.simulation.selectStage(3)
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(pancreas).wrappedValue.physiologyInputs, [40, 120])
    XCTAssertEqual(restored.binding(pancreas).wrappedValue.simulation.stage, 3)
    for bad in ["https://pubmed.ncbi.nlm.nih.gov/1/", "https://pubmed.ncbi.nlm.nih.gov/16461897/?x=1",
      "https://pubmed.ncbi.nlm.nih.gov.evil.invalid/16461897/"] {
      XCTAssertFalse(GalaxySSIHealthAtlas.trustedPlateSource(URL(string: bad)))
    }
    for language in ["en", "zh-Hans"] {
      var selection = state.binding(pancreas).wrappedValue; selection.tab = .simulation
      let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: pancreas, selection: selection,
        research: false, language: language)
      for line in GalaxySSIHealthAtlasPancreatic.context(pancreas.id, text: { GalaxySSIHealthAtlasText.get("health_atlas_" + $0, language) }) {
        XCTAssertTrue(prompt.contains(line))
      }
      selection.tab = .values
      XCTAssertEqual(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: pancreas, selection: selection,
        research: false, language: language), "")
    }
  }

  func testEndocrinePlatesPathsAndMechanismsPreserveStructuralAndCellIdentities() throws {
    let atlas = try completeCatalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.EndocrinePack.read(bundle: bundle))
    XCTAssertEqual(pack.plates.count, 18)
    XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 37)
    XCTAssertEqual(pack.plates.flatMap(\.markers).count, 4)
    XCTAssertEqual(pack.mechanisms.count, 4)
    for plate in pack.plates {
      let owner = try XCTUnwrap(plate.owner)
      XCTAssertEqual(atlas.plate(for: owner)?.asset, plate.asset)
      for feature in plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature = plate.labelTarget(feature.id, in: atlas) else { return XCTFail("Expected local explanation") }
      }
      for marker in plate.markers {
        guard case .anatomy(let id) = plate.labelTarget(marker.id, in: atlas) else { return XCTFail("Expected anatomy navigation") }
        XCTAssertNotNil(atlas.entry(id))
      }
      if atlas.entry(owner)?.kind == .cell { XCTAssertEqual(atlas.entry(owner)?.mechanism, owner) }
    }
    for (id, path) in pack.paths {
      let entry = try XCTUnwrap(atlas.entry(id))
      XCTAssertEqual(entry.mechanism, id); XCTAssertEqual(atlas.model(entry).kind, "secretion")
      XCTAssertEqual(path.steps.count, 4)
      for step in path.steps { if let id = step.destination { XCTAssertNotNil(atlas.entry(id)) } }
      let state = GalaxySSIHealthAtlasState(); state.binding(entry).wrappedValue.simulation.selectStage(3)
      if id == "thyroid-gland" { state.binding(entry).wrappedValue.physiologyInputs = [100, 300] }
      let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
      XCTAssertEqual(restored.binding(entry).wrappedValue.simulation.stage, 3)
      if id == "thyroid-gland" { XCTAssertEqual(restored.binding(entry).wrappedValue.physiologyInputs, [100, 300]) }
      for language in ["en", "zh-Hans"] {
        var selection = state.binding(entry).wrappedValue; selection.tab = .simulation
        let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selection,
          research: false, language: language)
        XCTAssertTrue(prompt.contains(GalaxySSIHealthAtlasText.get(path.scope, language)))
        selection.tab = .values
        XCTAssertEqual(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selection,
          research: false, language: language), "")
      }
    }
  }

  func testSensoryCellsAndRetinalViewsKeepDistinctLayerAndLocationContext() throws {
    let atlas = try completeCatalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.SensoryPack.read(bundle: bundle))
    XCTAssertEqual(pack.entries.count, 2); XCTAssertEqual(pack.mechanisms.count, 3)
    XCTAssertEqual(pack.plates.count, 16); XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 34)
    XCTAssertEqual(pack.plates.flatMap(\.markers).count, 3)
    let ganglionIndex = try XCTUnwrap(atlas.entries.firstIndex { $0.id == "cell-retinal-ganglion-cell" })
    XCTAssertEqual(Array(atlas.entries.dropFirst(ganglionIndex + 1).prefix(2).map(\.id)), GalaxySSIHealthAtlas.SensoryPack.relayIDs)
    for plate in pack.plates {
      let owner = try XCTUnwrap(plate.owner)
      XCTAssertEqual(atlas.plate(for: owner)?.asset, plate.asset)
      XCTAssertTrue(GalaxySSIHealthAtlas.trustedPlateSource(plate.source))
      for feature in plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature = plate.labelTarget(feature.id, in: atlas) else { return XCTFail("Expected explanation") }
      }
      for marker in plate.markers {
        guard case .anatomy(let id) = plate.labelTarget(marker.id, in: atlas) else { return XCTFail("Expected cell navigation") }
        XCTAssertNotNil(atlas.entry(id))
      }
    }
    for id in GalaxySSIHealthAtlas.SensoryPack.relayIDs {
      let cell = try XCTUnwrap(atlas.entry(id))
      XCTAssertEqual(cell.kind, .cell); XCTAssertEqual(cell.mechanism, id)
      XCTAssertEqual(atlas.model(cell).kind, "cell")
      for language in ["en", "zh-Hans"] {
        let name = GalaxySSIHealthAtlasText.get(cell.name, language)
        XCTAssertNotEqual(name, cell.name)
        XCTAssertTrue(atlas.search(name, kind: .cell, system: "sensory", language: language).contains { $0.id == id })
      }
    }
    let views = atlas.views(for: "retina")
    XCTAssertEqual(views.compactMap(\.viewKey), ["retina-layers", "retina-eye-context"])
    XCTAssertEqual(views.last?.asset, GalaxySSIHealthAtlasEyeOptics.plate.asset)
    XCTAssertTrue(views.last?.annotations.isEmpty == true)
    let retina = try XCTUnwrap(atlas.entry("retina")), rod = try XCTUnwrap(atlas.entry("cell-rod-photoreceptor"))
    XCTAssertEqual(retina.mechanism, retina.id)
    let state = GalaxySSIHealthAtlasState(), restored = GalaxySSIHealthAtlasState()
    state.binding(retina).wrappedValue.artworkView = "retina-eye-context"
    state.binding(retina).wrappedValue.simulation.selectStage(1)
    state.binding(rod).wrappedValue.physiologyInputs = [500]
    restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(retina).wrappedValue.artworkView, "retina-eye-context")
    XCTAssertEqual(restored.binding(retina).wrappedValue.simulation.stage, 1)
    XCTAssertEqual(restored.binding(rod).wrappedValue.physiologyInputs, [500])
    for language in ["en", "zh-Hans"] {
      var selection = state.binding(retina).wrappedValue; selection.tab = .structure
      let feature = GalaxySSIHealthAtlasText.get("health_atlas_sensory_retina_light_direction", language)
      let eye = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: retina, selection: selection, research: false, language: language)
      XCTAssertFalse(eye.contains(feature))
      selection.artworkView = "retina-layers"
      let layers = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: retina, selection: selection, research: false, language: language)
      XCTAssertTrue(layers.contains(feature))
      selection.tab = .values
      XCTAssertEqual(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: retina, selection: selection, research: false, language: language), "")
    }
    for bad in ["https://www.ncbi.nlm.nih.gov/books/NBK1/", "https://pubmed.ncbi.nlm.nih.gov/15987797/?x=1"] {
      XCTAssertFalse(GalaxySSIHealthAtlas.trustedPlateSource(URL(string: bad)))
    }
  }

  func testAllMicroscopicOwnersHaveDistinctDedicatedPicturesAndContextSectionsNavigate() throws {
    let atlas = try completeCatalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.TissueContextPack.read(bundle: bundle))
    XCTAssertEqual(pack.plates.count, 23); XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 46)
    XCTAssertEqual(pack.plates.flatMap(\.markers).count, 2)
    let microscopic = atlas.entries.filter { $0.kind == .cell || $0.kind == .fragment }
    let pictures = try microscopic.map { try XCTUnwrap(atlas.plate(for: $0.id)) }
    XCTAssertEqual(microscopic.count, 108); XCTAssertEqual(Set(pictures.map(\.asset)).count, 108)
    for (entry, picture) in zip(microscopic, pictures) {
      XCTAssertEqual(picture.owner, entry.id)
      XCTAssertNotNil(UIImage(named: picture.asset, in: bundle, compatibleWith: nil))
    }
    for plate in pack.plates {
      XCTAssertEqual(atlas.plate(for: plate.owner)?.asset, plate.asset)
      for feature in plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature = plate.labelTarget(feature.id, in: atlas) else { return XCTFail("Expected local explanation") }
      }
      for marker in plate.markers {
        guard case .anatomy(let id) = plate.labelTarget(marker.id, in: atlas) else { return XCTFail("Expected cell navigation") }
        XCTAssertEqual(atlas.entry(id)?.kind, .cell)
      }
    }
    let sweat = try XCTUnwrap(atlas.entry("sweat-glands")), state = GalaxySSIHealthAtlasState()
    state.binding(sweat).wrappedValue.simulation.phase = 0.9
    state.binding(sweat).wrappedValue.physiologyInputs = [200, 75]
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(sweat).wrappedValue.simulation.phase, 0.9)
    XCTAssertEqual(restored.binding(sweat).wrappedValue.physiologyInputs, [200, 75])
    XCTAssertEqual(GalaxySSIHealthAtlasSweatView.duct.cgPath.currentPoint, CGPoint(x: 192, y: 216))
    for id in ["sweat-glands", "hair-follicles"] {
      let entry = try XCTUnwrap(atlas.entry(id))
      XCTAssertEqual(entry.mechanism, id); XCTAssertEqual(atlas.model(entry).kind, "skin")
      for language in ["en", "zh-Hans"] {
        var selection = state.binding(entry).wrappedValue; selection.tab = .simulation
        let prompt = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selection, research: false, language: language)
        let scope = try XCTUnwrap(GalaxySSIHealthAtlasSweat.context(id, text: { GalaxySSIHealthAtlasText.get("health_atlas_" + $0, language) }))
        XCTAssertTrue(prompt.contains(scope)); XCTAssertFalse(prompt.contains("measuredAt"))
        selection.tab = .values
        XCTAssertEqual(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selection, research: false, language: language), "")
      }
    }
  }

  func testLymphOrganLessonsPreserveCanonicalLinksAndIndependentSelections() throws {
    let atlas = try completeCatalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.LymphPack.read(bundle: bundle))
    XCTAssertEqual(atlas.entries.count, 313); XCTAssertEqual(atlas.mechanisms.count, 192)
    XCTAssertEqual(pack.plates.count, 9); XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 30)
    XCTAssertEqual(pack.plates.flatMap(\.markers).count, 12)
    let state = GalaxySSIHealthAtlasState()
    for (index, id) in GalaxySSIHealthAtlas.LymphPack.owners.enumerated() {
      let entry = try XCTUnwrap(atlas.entry(id)), lesson = try XCTUnwrap(GalaxySSIHealthAtlasLymphLesson.forEntry(id))
      XCTAssertEqual(entry.mechanism, id); XCTAssertEqual(atlas.model(entry).kind, "lymphoid-organ")
      XCTAssertEqual(entry.related, lesson.plate.markers.map(\.id))
      XCTAssertEqual(atlas.plate(for: id)?.asset, lesson.plate.asset)
      XCTAssertNotNil(UIImage(named: lesson.plate.asset, in: bundle, compatibleWith: nil))
      for feature in lesson.plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature = lesson.plate.labelTarget(feature.id, in: atlas) else { return XCTFail("Expected local feature") }
      }
      for marker in lesson.plate.markers {
        guard case .anatomy = lesson.plate.labelTarget(marker.id, in: atlas) else { return XCTFail("Expected canonical link") }
      }
      for stage in 0..<4 {
        let phase = try XCTUnwrap(GalaxySSIHealthAtlasLymphLesson.Phase(Double(stage) / 4))
        XCTAssertEqual(phase.stage, stage); XCTAssertEqual(phase.fraction, 0)
        XCTAssertNotNil(lesson.feature(stage: stage))
        if let route = lesson.route(stage: stage) {
          let endpoint = try XCTUnwrap(route.commands.last?.points.last)
          XCTAssertEqual(GalaxySSIHealthAtlasLymphLessonView.path(route).cgPath.currentPoint, CGPoint(x: endpoint.x, y: endpoint.y))
        }
      }
      XCTAssertNil(lesson.feature(stage: -1)); XCTAssertNil(lesson.feature(stage: 4))
      state.binding(entry).wrappedValue.simulation.phase = Double(index) / 10
    }
    let vessel = try XCTUnwrap(atlas.entry("lymphatic-vessels"))
    state.binding(vessel).wrappedValue.physiologyInputs = [-20, 40]
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    for (index, id) in GalaxySSIHealthAtlas.LymphPack.owners.enumerated() {
      XCTAssertEqual(restored.binding(try XCTUnwrap(atlas.entry(id))).wrappedValue.simulation.phase, Double(index) / 10)
    }
    XCTAssertEqual(restored.binding(vessel).wrappedValue.physiologyInputs, [-20, 40])
    XCTAssertNil(GalaxySSIHealthAtlasLymphLesson.Phase(.nan))
    XCTAssertNil(GalaxySSIHealthAtlasLymphLesson.Phase(.infinity))
    XCTAssertEqual(GalaxySSIHealthAtlasLymphLesson.Phase(2)?.fraction, 1)
    XCTAssertEqual(GalaxySSIHealthAtlasLymphLesson.Phase(-1)?.stage, 0)
    XCTAssertNil(GalaxySSIHealthAtlasLymphLesson.forEntry("cell-b-cell"))
  }

  func testAlimentarySectionsShareRendererWithoutBorrowingLymphaticLessons() throws {
    let atlas = try completeCatalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let pack = try XCTUnwrap(GalaxySSIHealthAtlas.GutPack.read(bundle: bundle))
    XCTAssertEqual(pack.plates.count, 14); XCTAssertEqual(pack.plates.flatMap(\.annotations).count, 47)
    XCTAssertEqual(pack.plates.flatMap(\.markers).count, 29); XCTAssertEqual(pack.routes.count, 6)
    let state = GalaxySSIHealthAtlasState()
    for (index, id) in GalaxySSIHealthAtlas.GutPack.owners.enumerated() {
      let entry = try XCTUnwrap(atlas.entry(id)), lesson = try XCTUnwrap(GalaxySSIHealthAtlasSectionLesson.forEntry(id))
      XCTAssertEqual(entry.mechanism, id); XCTAssertEqual(atlas.model(entry).kind, "alimentary-organ")
      XCTAssertEqual(entry.related, lesson.plate.markers.map(\.id))
      XCTAssertEqual(atlas.plate(for: id)?.asset, lesson.plate.asset)
      for feature in lesson.plate.annotations {
        XCTAssertNil(atlas.entry(feature.id))
        guard case .feature = lesson.plate.labelTarget(feature.id, in: atlas) else { return XCTFail("Expected feature") }
      }
      for stage in 0..<4 {
        let feature = try XCTUnwrap(lesson.feature(stage: stage))
        if let route = lesson.route(stage: stage) {
          XCTAssertTrue(route.valid)
          let end = try XCTUnwrap(route.commands.last?.points.last)
          XCTAssertEqual(GalaxySSIHealthAtlasSectionLessonView.path(route).cgPath.currentPoint, CGPoint(x: end.x, y: end.y))
        }
        for language in ["en", "zh-Hans"] {
          let lines = GalaxySSIHealthAtlasSectionLesson.context(id, stage: stage, language: language)
          XCTAssertTrue(lines.contains(GalaxySSIHealthAtlasText.get(feature.title, language)))
          XCTAssertFalse(lines.contains { $0.contains("health_atlas_") })
          XCTAssertFalse(lines.contains(GalaxySSIHealthAtlasText.get("health_atlas_lymph_duct_orientation", language)))
        }
      }
      state.binding(entry).wrappedValue.simulation.phase = Double(index) / 20
    }
    let small = try XCTUnwrap(atlas.entry("small-intestine")), jejunum = try XCTUnwrap(atlas.entry("jejunum"))
    state.binding(small).wrappedValue.physiologyInputs = [0, 25, 20]
    state.binding(jejunum).wrappedValue.physiologyInputs = [24, 70, 120]
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    for (index, id) in GalaxySSIHealthAtlas.GutPack.owners.enumerated() {
      XCTAssertEqual(restored.binding(try XCTUnwrap(atlas.entry(id))).wrappedValue.simulation.phase, Double(index) / 20)
    }
    XCTAssertEqual(restored.binding(small).wrappedValue.physiologyInputs, [0, 25, 20])
    XCTAssertEqual(restored.binding(jejunum).wrappedValue.physiologyInputs, [24, 70, 120])
    XCTAssertNotNil(GalaxySSIHealthAtlasSectionLesson.forEntry("thoracic-duct"))
    XCTAssertNil(GalaxySSIHealthAtlasSectionLesson.forEntry("cell-enterocyte"))
  }

  func testEditorialArtworkRetainsResolutionTransparencyAndAllOneHundredNineteenHotspots() throws {
    let atlas = try completeCatalogue(), bundle = Bundle(for: GalaxySSIStore.self)
    let frames: [(String?, Int, Int)] = [(nil, 1024, 1536), ("heart", 1086, 1448),
      ("lungs", 1254, 1254), ("liver", 1254, 1254), ("kidneys", 1254, 1254),
      ("brain", 1254, 1254), ("gut", 1024, 1536), ("pancreas", 1536, 1024), ("urinary", 1024, 1536),
      ("nephron", 1173, 1341), ("alveoli", 1254, 1254), ("cell-pancreatic-beta-cell", 1254, 1254),
      ("cell-erythrocyte", 1254, 1254), ("cell-neuron", 1024, 1536), ("skin", 1536, 1024),
      ("sensory", 1199, 1312), ("immune", 1312, 1199), ("respiratory", 1145, 1374),
      ("digestive", 1246, 1263), ("endocrine", 1312, 1199), ("ear", 1536, 1024), ("eye", 1536, 1024),
      ("cell-inner-ear-hair-cell", 1024, 1536), ("cell-rod-photoreceptor", 1024, 1536), ("cell-cone-photoreceptor", 1024, 1536),
      ("nervous", 1024, 1536), ("cell-neutrophil", 1254, 1254), ("cell-macrophage", 1254, 1254),
      ("cell-eosinophil", 1254, 1254), ("cell-basophil", 1254, 1254)]
    let samples: [String: [CGPoint]] = [
      "pancreas": [CGPoint(x: 0.90, y: 0.72), CGPoint(x: 0.62, y: 0.30)],
      "urinary": [CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.66, y: 0.53)],
      "nephron": [CGPoint(x: 0.77, y: 0.45), CGPoint(x: 0.853, y: 0.644)],
      "alveoli": [CGPoint(x: 0.38, y: 0.10), CGPoint(x: 0.48, y: 0.48)],
      "cell-pancreatic-beta-cell": [CGPoint(x: 0.95, y: 0.10), CGPoint(x: 0.36, y: 0.39)],
      "cell-erythrocyte": [CGPoint(x: 0.50, y: 0.12), CGPoint(x: 0.50, y: 0.50)],
      "cell-neuron": [CGPoint(x: 0.08, y: 0.84), CGPoint(x: 0.38, y: 0.31)]
    ]
    func rgba(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
      let sample = try XCTUnwrap(image.cropping(to: CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1)))
      var pixel = [UInt8](repeating: 0, count: 4)
      try pixel.withUnsafeMutableBytes { bytes in
        let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      }
      return pixel
    }
    func alpha(_ image: CGImage, _ x: Int, _ y: Int) throws -> UInt8 { try rgba(image, x, y)[3] }
    var plates: [(GalaxySSIHealthAtlas.Plate, Int, Int)] = try frames.map { id, width, height in
      (try XCTUnwrap(atlas.plate(for: id)), width, height)
    }
    plates.append((GalaxySSIHealthAtlasHeartSection.section, 1254, 1254))
    for key in GalaxySSIHealthAtlas.MusculoskeletalPack.keys {
      let owner = key.hasPrefix("skeletal") ? "skeletal" : "muscle"
      let plate = try XCTUnwrap(atlas.plate(for: owner, viewKey: key))
      plates.append((plate, key == "skeletal-posterior" ? 887 : 1024, key == "skeletal-posterior" ? 1774 : 1536))
    }
    XCTAssertEqual(Set(plates.map { $0.0.asset }).count, 35)
    var count = 0
    for (plate, width, height) in plates {
      let image = try XCTUnwrap(UIImage(named: plate.asset, in: bundle, compatibleWith: nil)?.cgImage)
      XCTAssertEqual(image.width, width); XCTAssertEqual(image.height, height)
      for x in [0, width - 1] { for y in [0, height - 1] { XCTAssertLessThanOrEqual(try alpha(image, x, y), 4) } }
      for marker in plate.markers {
        XCTAssertGreaterThanOrEqual(try alpha(image, Int(marker.x * Double(width)), Int(marker.y * Double(height))), 200)
        XCTAssertNotNil(atlas.entry(marker.id)); count += 1
        if plate.owner == "nervous" {
          var matched = false
          for dx in -1...1 { for dy in -1...1 {
            let pixel = try rgba(image, Int(marker.x * Double(width)) + dx, Int(marker.y * Double(height)) + dy)
            let r = Int(pixel[0]), g = Int(pixel[1]), b = Int(pixel[2])
            matched = matched || (pixel[3] > 200 && (marker.id == "brain" ? b > r + 10 : r > b + 45 && g > b + 30))
          } }
          XCTAssertTrue(matched, marker.id)
        }
        if plate.owner == "muscle" {
          let pixel = try rgba(image, Int(marker.x * Double(width)), Int(marker.y * Double(height)))
          let r = Int(pixel[0]), g = Int(pixel[1]), b = Int(pixel[2])
          if marker.id == "gluteus-maximus" { XCTAssertGreaterThan(b, r + 15) }
          else if marker.id == "tendons" {
            XCTAssertGreaterThan(r, b + 30); XCTAssertGreaterThan(g, b + 25); XCTAssertLessThan(r - g, 40)
          } else { XCTAssertGreaterThan(r, g + 40); XCTAssertGreaterThan(g, b + 12) }
        }
      }
      if ["cell-neutrophil", "cell-macrophage", "cell-eosinophil", "cell-basophil"].contains(plate.owner ?? "") {
        for feature in plate.annotations {
          XCTAssertGreaterThan(try alpha(image, Int(feature.marker.x * Double(width)), Int(feature.marker.y * Double(height))), 200)
        }
      }
      if plate.id == "heart-section" {
        for marker in plate.markers + GalaxySSIHealthAtlasHeartSection.valves.markers {
          var matched = false
          for dx in -1...1 { for dy in -1...1 {
            let pixel = try rgba(image, Int(marker.x * Double(width)) + dx, Int(marker.y * Double(height)) + dy)
            let r = Int(pixel[0]), g = Int(pixel[1]), b = Int(pixel[2])
            let expected: Bool
            switch marker.id {
            case "right-atrium", "right-ventricle", "pulmonary-trunk": expected = b > r + 20
            case "aorta", "left-atrium", "left-ventricle": expected = r > g + 50 && r > b + 60
            default: expected = r > 229 && g > 201 && g > b && b > 158
            }
            matched = matched || (pixel[3] > 200 && expected)
          } }
          XCTAssertTrue(matched, marker.id)
        }
      }
      if plate.owner == "ear" {
        let lesson = try XCTUnwrap(GalaxySSIHealthAtlasSectionLesson.forEntry("ear"))
        func at(_ point: CGPoint) throws -> [UInt8] {
          try rgba(image, Int(point.x / CGFloat(lesson.artWidth) * CGFloat(width)), Int(point.y / 280 * CGFloat(height)))
        }
        for feature in lesson.plate.annotations {
          XCTAssertGreaterThan(try at(CGPoint(x: feature.marker.x * lesson.artWidth, y: feature.marker.y * 280))[3], 200)
        }
        for route in lesson.routes {
          for index in 0...12 {
            let flow = try XCTUnwrap(GalaxySSIHealthAtlasSectionLessonView.flow(route, fraction: Double(index) / 12, width: lesson.artWidth))
            XCTAssertGreaterThan(try at(flow.point)[3], 200)
          }
        }
        let last = try XCTUnwrap(lesson.routes.last)
        let endpoint = try XCTUnwrap(GalaxySSIHealthAtlasSectionLessonView.flow(last, fraction: 1, width: lesson.artWidth))
        let colour = try at(endpoint.point)
        XCTAssertGreaterThan(Int(colour[0]), Int(colour[2]) + 45)
      }
      if let id = plate.owner, let sample = samples[id] {
        XCTAssertLessThanOrEqual(try alpha(image, Int(sample[0].x * CGFloat(width)), Int(sample[0].y * CGFloat(height))), 4)
        XCTAssertGreaterThanOrEqual(try alpha(image, Int(sample[1].x * CGFloat(width)), Int(sample[1].y * CGFloat(height))), 200)
      }
    }
    XCTAssertEqual(count, 119)
    XCTAssertTrue(try XCTUnwrap(atlas.plate(for: nil)).markers.contains { $0.id == "lungs" })
  }

  func testSectionFlowUsesCurveTangentsAndRewindClearsTheTrail() throws {
    typealias Lesson = GalaxySSIHealthAtlasSectionLesson
    typealias Diagram = GalaxySSIHealthAtlasSectionLessonView
    let quadratic = Lesson.Route(start: .init(x: 10, y: 10),
      commands: [.init(kind: .quad, points: [.init(x: 10, y: 30), .init(x: 30, y: 30)])])
    let start = try XCTUnwrap(Diagram.flow(quadratic, fraction: 0))
    XCTAssertTrue(start.trail.isEmpty); XCTAssertFalse(start.tip.isEmpty)
    XCTAssertEqual(start.point, CGPoint(x: 10, y: 10))
    XCTAssertEqual(start.direction.dx, 0, accuracy: 1e-9); XCTAssertEqual(start.direction.dy, 1, accuracy: 1e-9)
    let end = try XCTUnwrap(Diagram.flow(quadratic, fraction: 1))
    XCTAssertEqual(end.point, CGPoint(x: 30, y: 30))
    XCTAssertEqual(end.direction.dx, 1, accuracy: 1e-9); XCTAssertEqual(end.direction.dy, 0, accuracy: 1e-9)
    let advancing = try XCTUnwrap(Diagram.flow(quadratic, fraction: 0.8))
    XCTAssertFalse(advancing.trail.isEmpty)
    XCTAssertGreaterThan(advancing.point.x, start.point.x)
    XCTAssertTrue(try XCTUnwrap(Diagram.flow(quadratic, fraction: 0)).trail.isEmpty)
    for invalid in [Double.nan, .infinity, -0.1, 1.1] { XCTAssertNil(Diagram.flow(quadratic, fraction: invalid)) }
    let cubic = Lesson.Route(start: .init(x: 20, y: 20), commands: [.init(kind: .cubic,
      points: [.init(x: 40, y: 20), .init(x: 60, y: 40), .init(x: 60, y: 60)])])
    XCTAssertEqual(try XCTUnwrap(Diagram.flow(cubic, fraction: 0)).direction.dx, 1, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(Diagram.flow(cubic, fraction: 1)).direction.dy, 1, accuracy: 1e-9)
    for id in GalaxySSIHealthAtlas.LymphPack.owners + GalaxySSIHealthAtlas.GutPack.owners {
      let lesson = try XCTUnwrap(Lesson.forEntry(id))
      for route in lesson.routes {
        for fraction in [0.0, 0.2, 0.8, 1] {
          let flow = try XCTUnwrap(Diagram.flow(route, fraction: fraction))
          XCTAssertEqual(hypot(flow.direction.dx, flow.direction.dy), 1, accuracy: 1e-8)
          XCTAssertEqual(flow.trail.isEmpty, fraction == 0)
        }
      }
    }
  }

  func testSensorySectionsUseWideEarTracksAndRetinalCircuitStageWithoutReplacingNavigation() throws {
    typealias Lesson = GalaxySSIHealthAtlasSectionLesson
    typealias Diagram = GalaxySSIHealthAtlasSectionLessonView
    let atlas = try completeCatalogue(), state = GalaxySSIHealthAtlasState()
    let ear = try XCTUnwrap(Lesson.forEntry("ear")), retina = try XCTUnwrap(Lesson.forEntry("retina"))
    XCTAssertEqual(ear.artWidth, 420); XCTAssertEqual(ear.routes.count, 4)
    XCTAssertEqual(ear.stageFeatures, [0, 1, 2, 3]); XCTAssertEqual(retina.stageFeatures, [0, 1, 2, 3])
    XCTAssertEqual(retina.artWidth, 360); XCTAssertTrue(retina.routes.isEmpty); XCTAssertTrue(retina.plate.markers.isEmpty)
    XCTAssertEqual(retina.plate.annotations.map(\.id),
      ["cell-rod-photoreceptor", "retina-relay-layer", "cell-cone-photoreceptor", "cell-retinal-ganglion-cell"])
    XCTAssertEqual(atlas.plate(for: "retina")?.markers.count, 3)
    XCTAssertEqual(atlas.plate(for: "ear")?.markers.count, 5)
    for lesson in [ear, retina] {
      for stage in 0..<4 {
        let feature = try XCTUnwrap(lesson.feature(stage: stage))
        for language in ["en", "zh-Hans"] {
          XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(feature.title, language), feature.title)
          XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(feature.explanation, language), feature.explanation)
        }
        if let route = lesson.route(stage: stage) {
          XCTAssertTrue(route.fits(width: lesson.artWidth))
          for fraction in [0.0, 0.4, 1] { XCTAssertNotNil(Diagram.flow(route, fraction: fraction, width: lesson.artWidth)) }
        }
      }
    }
    let last = try XCTUnwrap(ear.routes.last)
    XCTAssertFalse(last.valid); XCTAssertNil(Diagram.flow(last, fraction: 0.5))
    XCTAssertEqual(Diagram.path(last, width: 420).cgPath.currentPoint, CGPoint(x: 411, y: 135))
    XCTAssertNil(Diagram.flow(last, fraction: 0.5, width: .nan))
    XCTAssertNil(Diagram.flow(last, fraction: 0.5, width: 0))
    let earEntry = try XCTUnwrap(atlas.entry("ear")), retinaEntry = try XCTUnwrap(atlas.entry("retina"))
    state.binding(earEntry).wrappedValue.simulation.phase = 0.75
    state.binding(earEntry).wrappedValue.physiologyInputs = [65, 40, 150]
    state.binding(retinaEntry).wrappedValue.simulation.phase = 0.5
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(earEntry).wrappedValue.simulation.stage, 3)
    XCTAssertEqual(restored.binding(retinaEntry).wrappedValue.simulation.stage, 2)
    XCTAssertEqual(restored.binding(earEntry).wrappedValue.physiologyInputs, [65, 40, 150])
    XCTAssertNil(Lesson.forEntry("eye")); XCTAssertNil(Lesson.forEntry("cell-cochlear-hair-cell"))
  }

  func testSplitCalloutRailsMeasureRealLocalizedTextAndKeepLeadersInTheirHalf() throws {
    let atlas = try completeCatalogue()
    for id in ["eye", "ear", "sensory", "immune", "endocrine"] {
      let plate = try XCTUnwrap(atlas.plate(for: id))
      XCTAssertTrue(plate.splitCallouts)
      for language in ["en", "zh-Hans"] {
        let names = try plate.markers.map { marker in
          GalaxySSIHealthAtlasText.get(try XCTUnwrap(atlas.entry(marker.id)).name, language)
        }
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
          let traits = UITraitCollection(preferredContentSizeCategory: category)
          let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
          let labels = names.map { name -> UILabel in
            let label = UILabel(); label.text = name; label.font = font
            label.numberOfLines = 0; label.lineBreakMode = .byWordWrapping; return label
          }
          for width in [CGFloat(320), 390, 768] {
            let plan = try XCTUnwrap(GalaxySSIHealthAtlasCalloutLayout.make(width: width, aspectRatio: plate.aspectRatio,
              anchors: plate.markers.map { CGPoint(x: $0.x, y: $0.y) }, splitRequested: plate.splitCallouts,
              accessibility: category.isAccessibilityCategory,
              preferredWidths: names.map { ($0 as NSString).size(withAttributes: [.font: font]).width + 6 },
              measureHeight: { labels[$0].sizeThatFits(CGSize(width: max(1, $1 - 6), height: .greatestFiniteMagnitude)).height + 16 }))
            XCTAssertTrue(plan.split); XCTAssertFalse(plan.left.isEmpty); XCTAssertFalse(plan.right.isEmpty)
            XCTAssertGreaterThanOrEqual(plan.imageRect.width, width / 2)
            XCTAssertLessThanOrEqual(plan.leftWidth, floor(width * 0.24))
            XCTAssertLessThanOrEqual(plan.rightWidth, floor(width * 0.24))
            for rail in [plan.left, plan.right] {
              var bottom: CGFloat = 0
              for index in rail {
                let frame = plan.labelFrames[index]
                XCTAssertGreaterThanOrEqual(frame.minY, bottom)
                XCTAssertGreaterThanOrEqual(frame.height, 48); XCTAssertGreaterThanOrEqual(frame.width, 48)
                XCTAssertGreaterThanOrEqual(frame.minX, 0); XCTAssertLessThanOrEqual(frame.maxX, width)
                XCTAssertLessThanOrEqual(frame.maxY, plan.height)
                XCTAssertGreaterThanOrEqual(frame.height, labels[index].sizeThatFits(CGSize(width: frame.width - 6, height: .greatestFiniteMagnitude)).height + 16)
                bottom = frame.maxY + 8
              }
            }
            let points = plate.markers.map { CGPoint(x: plan.imageRect.minX + plan.imageRect.width * CGFloat($0.x),
              y: plan.imageRect.minY + plan.imageRect.height * CGFloat($0.y)) }
            for (index, start) in points.enumerated() {
              let left = plan.left.contains(index), frame = plan.labelFrames[index]
              let end = CGPoint(x: left ? frame.maxX : frame.minX, y: frame.midY)
              let obstacles = points.enumerated().filter { $0.offset != index }.map(\.element)
              let route = GalaxySSIHealthAtlasLeaderRoutes.route(start: start, end: end, obstacles: obstacles, clearance: 8,
                minX: left ? -.infinity : plan.imageRect.midX, maxX: left ? plan.imageRect.midX : .infinity)
              XCTAssertGreaterThanOrEqual(route.count, 2)
              XCTAssertEqual(route.first, start); XCTAssertEqual(route.last, end)
              XCTAssertTrue(route.allSatisfy { left ? $0.x <= plan.imageRect.midX : $0.x >= plan.imageRect.midX })
              for (a, b) in zip(route, route.dropFirst()) {
                for obstacle in obstacles {
                  XCTAssertGreaterThanOrEqual(GalaxySSIHealthAtlasLeaderRoutes.segmentDistance(obstacle, start: a, end: b), 8 - 1e-6)
                }
              }
            }
          }
        }
      }
    }
    XCTAssertTrue(GalaxySSIHealthAtlasRetinaPath.eyeContext.splitCallouts)
    for id in ["heart", "skin", "respiratory", "digestive", "retina"] {
      XCTAssertFalse(try XCTUnwrap(atlas.plate(for: id)).splitCallouts)
    }
  }

  func testSplitCalloutFallbackAndBoundedLeaderValidation() throws {
    let anchors = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.3, y: 0.8)]
    let plan = try XCTUnwrap(GalaxySSIHealthAtlasCalloutLayout.make(width: 320, aspectRatio: 1,
      anchors: anchors, splitRequested: true, accessibility: false, preferredWidths: [50, 70],
      measureHeight: { _, _ in 48 }))
    XCTAssertFalse(plan.split); XCTAssertTrue(plan.left.isEmpty); XCTAssertEqual(plan.right, [0, 1])
    XCTAssertEqual(plan.rightWidth, 320 * 0.36, accuracy: 1e-6)
    let independent = try XCTUnwrap(GalaxySSIHealthAtlasCalloutLayout.make(width: 400, aspectRatio: 1.5,
      anchors: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)], splitRequested: true, accessibility: false,
      preferredWidths: [48, 72], measureHeight: { _, _ in 48 }))
    XCTAssertEqual(independent.leftWidth, 48); XCTAssertEqual(independent.rightWidth, 72)
    XCTAssertNil(GalaxySSIHealthAtlasCalloutLayout.make(width: .nan, aspectRatio: 1,
      anchors: anchors, splitRequested: true, accessibility: false, preferredWidths: [50, 70], measureHeight: { _, _ in 48 }))
    XCTAssertNil(GalaxySSIHealthAtlasCalloutLayout.make(width: 320, aspectRatio: 1,
      anchors: anchors, splitRequested: true, accessibility: false, preferredWidths: [50, 70], measureHeight: { _, _ in .nan }))
    for scale in [CGFloat(0.5), 1, 2, 3] {
      let start = CGPoint(x: 60 * scale, y: 0), end = CGPoint(x: 110 * scale, y: 0)
      let route = GalaxySSIHealthAtlasLeaderRoutes.route(start: start, end: end,
        obstacles: [CGPoint(x: 80 * scale, y: 0)], clearance: 8 * scale, minX: 55 * scale, maxX: 120 * scale)
      XCTAssertEqual(route.first, start); XCTAssertEqual(route.last, end); XCTAssertGreaterThan(route.count, 2)
      XCTAssertTrue(route.allSatisfy { (55 * scale...120 * scale).contains($0.x) })
    }
    XCTAssertTrue(GalaxySSIHealthAtlasLeaderRoutes.route(start: .zero, end: CGPoint(x: 1, y: 1),
      obstacles: [], clearance: 8, minX: 2).isEmpty)
    XCTAssertTrue(GalaxySSIHealthAtlasLeaderRoutes.route(start: .zero, end: CGPoint(x: 1, y: 1),
      obstacles: [], clearance: 8, minX: .nan).isEmpty)
    var object: [String: Any] = ["id": "fixture", "asset": "Fixture", "owner": "eye", "viewLabel": "fixture",
      "entryIDs": ["eye"], "aspectRatio": 1, "markers": []]
    XCTAssertFalse(try JSONDecoder().decode(GalaxySSIHealthAtlas.Plate.self, from: JSONSerialization.data(withJSONObject: object)).splitCallouts)
    object["splitCallouts"] = true
    XCTAssertTrue(try JSONDecoder().decode(GalaxySSIHealthAtlas.Plate.self, from: JSONSerialization.data(withJSONObject: object)).splitCallouts)
  }

  func testPortraitSensoryStagesHighlightTheirOwnOutputsWithoutChangingPhotonInputs() throws {
    typealias Lesson = GalaxySSIHealthAtlasSectionLesson
    let atlas = try completeCatalogue(), state = GalaxySSIHealthAtlasState()
    let fixtures = [
      ("cell-inner-ear-hair-cell", [0, 0, 2, 1], "hair-afferent-contact"),
      ("cell-rod-photoreceptor", [0, 0, 0, 1], "rod-spherule"),
      ("cell-cone-photoreceptor", [0, 0, 0, 1], "cone-pedicle")
    ]
    for (id, stages, output) in fixtures {
      let entry = try XCTUnwrap(atlas.entry(id)), lesson = try XCTUnwrap(Lesson.forEntry(id))
      XCTAssertEqual(lesson.plate.owner, id); XCTAssertEqual(lesson.plate.aspectRatio, 2.0 / 3)
      XCTAssertEqual(lesson.artWidth, 280); XCTAssertEqual(lesson.artHeight, 420)
      XCTAssertEqual(lesson.stageFeatures, stages); XCTAssertTrue(lesson.routes.isEmpty)
      XCTAssertEqual(lesson.feature(stage: 3)?.id, output)
      XCTAssertNotEqual(lesson.feature(stage: 0)?.id, lesson.feature(stage: 3)?.id)
      XCTAssertEqual(atlas.plate(for: id)?.annotations.count, 2)
      XCTAssertEqual(lesson.plate.annotations.count, id == "cell-inner-ear-hair-cell" ? 3 : 2)
      if id == "cell-inner-ear-hair-cell" { XCTAssertEqual(lesson.feature(stage: 2)?.id, "hair-cell-receptor-body") }
      for stage in 0..<4 {
        let feature = try XCTUnwrap(lesson.feature(stage: stage))
        XCTAssertTrue((0...1).contains(feature.marker.x)); XCTAssertTrue((0...1).contains(feature.marker.y))
        for language in ["en", "zh-Hans"] {
          XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(feature.title, language), feature.title)
          XCTAssertNotEqual(GalaxySSIHealthAtlasText.get(feature.explanation, language), feature.explanation)
        }
      }
      state.binding(entry).wrappedValue.simulation.phase = 0.9
    }
    let rod = try XCTUnwrap(atlas.entry("cell-rod-photoreceptor"))
    state.binding(rod).wrappedValue.physiologyInputs = [225]
    state.binding(rod).wrappedValue.simulation.selectStage(0)
    XCTAssertEqual(state.binding(rod).wrappedValue.physiologyInputs, [225])
    let restored = GalaxySSIHealthAtlasState(); restored.restore(state.serialized, atlas: atlas)
    XCTAssertEqual(restored.binding(rod).wrappedValue.simulation.stage, 0)
    XCTAssertEqual(restored.binding(rod).wrappedValue.physiologyInputs, [225])
    for id in ["cell-inner-ear-hair-cell", "cell-cone-photoreceptor"] {
      let entry = try XCTUnwrap(atlas.entry(id))
      XCTAssertEqual(restored.binding(entry).wrappedValue.simulation.stage, 3)
      XCTAssertNil(restored.binding(entry).wrappedValue.physiologyInputs)
    }
    let route = Lesson.Route(start: .init(x: 140, y: 20),
      commands: [.init(kind: .line, points: [.init(x: 140, y: 400)])])
    XCTAssertFalse(route.valid); XCTAssertTrue(route.fits(width: 280, height: 420))
    XCTAssertNil(GalaxySSIHealthAtlasSectionLessonView.flow(route, fraction: 0.5, width: 280))
    let point = try XCTUnwrap(GalaxySSIHealthAtlasSectionLessonView.flow(route, fraction: 0.5, width: 280, height: 420)).point
    XCTAssertEqual(point, CGPoint(x: 140, y: 210))
    XCTAssertFalse(route.fits(width: 280, height: .nan)); XCTAssertFalse(route.fits(width: 280, height: 0))
    for id in GalaxySSIHealthAtlas.LymphPack.owners + GalaxySSIHealthAtlas.GutPack.owners {
      XCTAssertEqual(try XCTUnwrap(Lesson.forEntry(id)).artHeight, 280)
    }
  }

  func testOneUseHandoffIsBoundedOwnerBoundAndExpires() throws {
    let handoff = GalaxySSIHealthAtlasAgentHandoff()
    let token = try XCTUnwrap(handoff.prepare(owner: "a", conversation: "c", prompt: "Public teaching", now: 10))
    XCTAssertNil(handoff.consume(token, owner: "b", conversation: "c", now: 11))
    XCTAssertNil(handoff.consume(token, owner: "a", conversation: "c", now: 11))
    let expired = try XCTUnwrap(handoff.prepare(owner: "a", conversation: "c", prompt: "Public teaching", now: 12))
    XCTAssertNil(handoff.consume(expired, owner: "a", conversation: "c", now: 133))
    let success = try XCTUnwrap(handoff.prepare(owner: "a", conversation: "c", prompt: "Public teaching", now: 140))
    XCTAssertEqual(handoff.consume(success, owner: "a", conversation: "c", now: 141)?.prompt, "Public teaching")
    XCTAssertNil(handoff.consume(success, owner: "a", conversation: "c", now: 141))
    for _ in 0..<8 { XCTAssertNotNil(handoff.prepare(owner: "a", conversation: "c", prompt: "Public", now: 150)) }
    XCTAssertNil(handoff.prepare(owner: "a", conversation: "c", prompt: "Public", now: 150))
    XCTAssertNotNil(handoff.prepare(owner: "a", conversation: "c", prompt: "Public", now: 271))
  }

  func testPublicQuestionCarriesModelLimitsAndSourcesWithoutHealthArchive() throws {
    let atlas = try catalogue(), heart = try XCTUnwrap(atlas.entry("heart"))
    var selection = GalaxySSIHealthAtlasState.Selection()
    selection.research = .drugs
    let question = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection, research: true, language: "en")
    XCTAssertTrue(question.contains("single-compartment"))
    XCTAssertTrue(question.contains("after 8 h, 25"))
    XCTAssertTrue(question.contains("pharmacologyeducation.org"))
    XCTAssertTrue(question.contains("not personal health data"))
    XCTAssertFalse(question.contains("measuredAt"))
  }
}
