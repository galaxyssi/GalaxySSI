import XCTest
import UIKit
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAtlasTests: XCTestCase {
  private func catalogue() throws -> GalaxySSIHealthAtlas {
    try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self), includeExtensions: false)
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
    XCTAssertEqual(cells.filter { $0.kind == .cell }.count, 105)
    XCTAssertEqual(cells.filter { $0.kind == .fragment }.count, 1)
    XCTAssertEqual(atlas.mechanisms.filter { ["cell", "fragment"].contains($0.kind) }.count, 106)
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
    let bundle = Bundle(for: GalaxySSIStore.self), atlas = try catalogue()
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

  func testTransportCellPlatesKeepLocalFeaturesAndExplicitSubtypeCaptions() throws {
    let bundle = Bundle(for: GalaxySSIStore.self), atlas = try catalogue()
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
