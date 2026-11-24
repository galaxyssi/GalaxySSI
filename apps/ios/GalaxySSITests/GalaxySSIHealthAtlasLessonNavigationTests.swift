import XCTest
import SwiftUI
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAtlasLessonNavigationTests: XCTestCase {
  private func fixture() throws -> (GalaxySSIHealthAtlas, GalaxySSIHealthAtlasFunctionCatalogue, GalaxySSIHealthAtlas.Entry) {
    let bundle = Bundle(for: GalaxySSIStore.self)
    let atlas = try GalaxySSIHealthAtlas.load(bundle: bundle)
    let catalogue = try XCTUnwrap(GalaxySSIHealthAtlasFunctionCatalogue.read(bundle: bundle))
    return (atlas, catalogue, try XCTUnwrap(atlas.entry("aorta")))
  }
  func testSameOrganReturnRestoresOriginButRetainsDestinationProgressAndIgnoresLateWrites() throws {
    let (atlas, catalogue, aorta) = try fixture(), state = GalaxySSIHealthAtlasState()
    state.recordDetail(aorta, depth: 1)
    var source = state.binding(aorta).wrappedValue
    var course = GalaxySSIHealthAtlasFunctionSelection()
    course.choose("ARTERIAL_PULSE", entryID: aorta.id, catalogue: catalogue)
    course.save(0.4, storyID: "ARTERIAL_PULSE", entryID: aorta.id, catalogue: catalogue)
    source.tab = .function; source.functionSelection = course
    state.binding(aorta).wrappedValue = source
    state.recordFunctionPhase(entryID: aorta.id, storyID: "ARTERIAL_PULSE", phase: 0.43, depth: 1)
    let related = try XCTUnwrap(catalogue.story("ARTERIAL_PULSE")?.related.first { $0.entryID == aorta.id })
    XCTAssertTrue(state.openRelatedLesson(origin: aorta, depth: 1, related: related, scroll: 887.5, atlas: atlas, catalogue: catalogue))
    XCTAssertEqual(state.detailBinding(aorta, depth: 1).wrappedValue.functionSelection?.selected, "ARTERIAL_PULSE")
    XCTAssertEqual(state.detailBinding(aorta, depth: 2).wrappedValue.functionSelection?.selected, "HEARTBEAT")
    let child = state.detailBinding(aorta, depth: 2)
    var destination = child.wrappedValue
    destination.functionSelection?.save(0.78, storyID: "HEARTBEAT", entryID: aorta.id, catalogue: catalogue)
    destination.simulation.speed = 1.5
    child.wrappedValue = destination
    let restored = GalaxySSIHealthAtlasState()
    restored.restore("{}", atlas: atlas)
    restored.restoreLessonNavigation(state.lessonNavigationSerialized, atlas: atlas)
    XCTAssertEqual(restored.lessonNavigation.path.count, 2)
    XCTAssertEqual(restored.detailBinding(aorta, depth: 1).wrappedValue.functionSelection?.selected, "ARTERIAL_PULSE")
    XCTAssertEqual(restored.detailBinding(aorta, depth: 2).wrappedValue.functionSelection?.selected, "HEARTBEAT")
    let location = GalaxySSIHealthAtlasLessonNavigation.Location(entryID: aorta.id, depth: 1)
    for value in [state, restored] {
      value.closeRelatedLesson(location)
      let after = value.binding(aorta).wrappedValue
      XCTAssertEqual(after.functionSelection?.selected, "ARTERIAL_PULSE")
      XCTAssertEqual(after.functionSelection?.phases["ARTERIAL_PULSE"], 0.43)
      XCTAssertEqual(after.functionSelection?.phases["HEARTBEAT"], 0.78)
      XCTAssertEqual(after.simulation.speed, 1.5)
      XCTAssertEqual(value.lessonReturnScroll[location.key], 887.5)
      var late = value.detailBinding(aorta, depth: 2).wrappedValue
      late.functionSelection?.choose("HEARTBEAT", entryID: aorta.id, catalogue: catalogue)
      value.detailBinding(aorta, depth: 2).wrappedValue = late
      value.recordFunctionPhase(entryID: aorta.id, storyID: "ARTERIAL_PULSE", phase: 0.99, depth: 2)
      XCTAssertEqual(value.functionSnapshot(aorta, depth: 1).functionSelection?.selected, "ARTERIAL_PULSE")
      XCTAssertEqual(value.functionSnapshot(aorta, depth: 1).functionSelection?.phases["ARTERIAL_PULSE"], 0.43)
    }
  }
  func testRestoredOrdinaryAncestorAndCrossEntryRelatedReturnKeepDistinctContexts() throws {
    let (atlas, catalogue, aorta) = try fixture(), state = GalaxySSIHealthAtlasState()
    let brain = try XCTUnwrap(atlas.entry("brain")), capillaries = try XCTUnwrap(atlas.entry("capillaries"))
    state.recordDetail(brain, depth: 1); state.recordDetail(aorta, depth: 2)
    var selection = state.binding(aorta).wrappedValue
    selection.tab = .function
    selection.functionSelection = .init()
    selection.functionSelection?.choose("ARTERIAL_PULSE", entryID: aorta.id, catalogue: catalogue)
    selection.functionSelection?.save(0.4, storyID: "ARTERIAL_PULSE", entryID: aorta.id, catalogue: catalogue)
    state.binding(aorta).wrappedValue = selection
    let related = try XCTUnwrap(catalogue.story("ARTERIAL_PULSE")?.related.first { $0.entryID == capillaries.id })
    XCTAssertTrue(state.openRelatedLesson(origin: aorta, depth: 2, related: related, scroll: 400, atlas: atlas, catalogue: catalogue))
    let restored = GalaxySSIHealthAtlasState()
    restored.restore(state.serialized, atlas: atlas)
    restored.restoreLessonNavigation(state.lessonNavigationSerialized, atlas: atlas)
    let root = GalaxySSIHealthAtlasLessonNavigation.Location(entryID: brain.id, depth: 1)
    XCTAssertEqual(restored.restoredDetailChildren[root.key]?.entryID, aorta.id)
    XCTAssertEqual(restored.lessonNavigation.path.last?.entryID, capillaries.id)
    XCTAssertEqual(restored.binding(capillaries).wrappedValue.functionSelection?.selected, "ENDOTHELIAL_EXCHANGE")
    restored.closeRelatedLesson(.init(entryID: aorta.id, depth: 2))
    XCTAssertEqual(restored.binding(aorta).wrappedValue.functionSelection?.selected, "ARTERIAL_PULSE")
    restored.closeRestoredDetail(root)
    XCTAssertEqual(restored.lessonNavigation.path, [root])
  }
  func testRetappingSelectedDetailTabDoesNotPauseOrMutateState() throws {
    let (_, _, aorta) = try fixture(), state = GalaxySSIHealthAtlasState()
    state.recordDetail(aorta, depth: 1)
    state.binding(aorta).wrappedValue.tab = .function
    var paused = false
    state.playback.claim("fixture", now: 100, pause: { _ in paused = true })
    XCTAssertFalse(state.selectDetailTab(aorta, depth: 1, tab: .function))
    XCTAssertEqual(state.playback.owner, "fixture"); XCTAssertFalse(paused)
    XCTAssertTrue(state.selectDetailTab(aorta, depth: 1, tab: .structure))
    XCTAssertTrue(paused); XCTAssertNil(state.playback.owner)
  }
  func testNavigationArchiveRejectsUnboundedUnknownAndNoncontiguousPaths() throws {
    let (atlas, _, aorta) = try fixture(), state = GalaxySSIHealthAtlasState()
    var archive = GalaxySSIHealthAtlasLessonNavigation()
    func load(_ value: GalaxySSIHealthAtlasLessonNavigation) throws {
      state.restoreLessonNavigation(String(decoding: try JSONEncoder().encode(value), as: UTF8.self), atlas: atlas)
      XCTAssertTrue(state.lessonNavigation.path.isEmpty)
    }
    archive.path = [.init(entryID: "unknown-entry", depth: 1)]; try load(archive)
    archive.path = [.init(entryID: aorta.id, depth: 1), .init(entryID: aorta.id, depth: 3)]; try load(archive)
    archive.path = (1...33).map { .init(entryID: aorta.id, depth: $0) }; try load(archive)
    archive.path = [.init(entryID: aorta.id, depth: 1)]; archive.schema = 2; try load(archive)
    archive.schema = 1
    let location = GalaxySSIHealthAtlasLessonNavigation.Location(entryID: aorta.id, depth: 1)
    archive.path = [location, .init(entryID: aorta.id, depth: 2)]
    let invalid = GalaxySSIHealthAtlasLessonNavigation.Return(origin: location, selection: .init(), scroll: 0,
      targetID: aorta.id, targetStory: "UNKNOWN_COURSE")
    archive.returns = [location.key: invalid]; try load(archive)
    archive.returns = ["wrong-context": invalid]; try load(archive)
    state.restoreLessonNavigation(String(repeating: "x", count: 128_001), atlas: atlas)
    XCTAssertTrue(state.lessonNavigation.path.isEmpty)
  }
  func testSearchCancelAndResultBackPreserveOriginVariantScrollAndPhase() throws {
    let (atlas, catalogue, aorta) = try fixture(), state = GalaxySSIHealthAtlasState()
    state.recordDetail(aorta, depth: 1)
    var selection = state.binding(aorta).wrappedValue
    selection.tab = .function; selection.zoom = 2; selection.layers = false
    selection.artworkView = atlas.views(for: aorta.id).first?.viewKey
    selection.functionSelection = .init()
    selection.functionSelection?.choose("ARTERIAL_PULSE", entryID: aorta.id, catalogue: catalogue)
    state.binding(aorta).wrappedValue = selection
    state.recordFunctionPhase(entryID: aorta.id, storyID: "ARTERIAL_PULSE", phase: 0.43, depth: 1)
    state.beginCatalogueSearch(aorta, depth: 1, scroll: 335)
    let saved = try XCTUnwrap(state.lessonNavigation.search)
    XCTAssertEqual(saved.selection.functionSelection?.phases["ARTERIAL_PULSE"], 0.43)
    let restored = GalaxySSIHealthAtlasState()
    restored.restoreLessonNavigation(state.lessonNavigationSerialized, atlas: atlas)
    XCTAssertEqual(restored.lessonNavigation.search, saved)
    restored.cancelCatalogueSearch()
    XCTAssertEqual(restored.binding(aorta).wrappedValue.zoom, 2)
    XCTAssertEqual(restored.lessonReturnScroll[saved.origin.key], 335)
    XCTAssertTrue(restored.openCatalogueResult(aorta.id, from: saved, atlas: atlas))
    XCTAssertEqual(restored.detailBinding(aorta, depth: 1).wrappedValue.tab, .function)
    XCTAssertEqual(restored.detailBinding(aorta, depth: 2).wrappedValue.tab, .structure)
    let replay = GalaxySSIHealthAtlasState()
    replay.restoreLessonNavigation(restored.lessonNavigationSerialized, atlas: atlas)
    XCTAssertEqual(replay.lessonNavigation.path.count, 2)
    replay.closeRelatedLesson(saved.origin)
    XCTAssertEqual(replay.binding(aorta).wrappedValue.tab, .function)
    XCTAssertEqual(replay.binding(aorta).wrappedValue.functionSelection?.phases["ARTERIAL_PULSE"], 0.43)
    XCTAssertEqual(replay.binding(aorta).wrappedValue.artworkView, selection.artworkView)
    XCTAssertFalse(replay.binding(aorta).wrappedValue.layers)
    XCTAssertEqual(replay.lessonNavigation.path.count, 1)
  }
  func testFigureOverlapAndBottomCalloutsReserveLegendWithoutChangingDefaults() throws {
    XCTAssertEqual(GalaxySSIHealthAtlasFigureLayout.sharedHeight(art: 100, legend: 80), 28)
    XCTAssertEqual(GalaxySSIHealthAtlasFigureLayout.sharedHeight(art: 10, legend: 80), 10)
    XCTAssertEqual(GalaxySSIHealthAtlasFigureLayout.sharedHeight(art: .nan, legend: 80), 0)
    let layout = try XCTUnwrap(GalaxySSIHealthAtlasCalloutLayout.make(width: 320, aspectRatio: 1,
      anchors: [CGPoint(x: 0.8, y: 1)], splitRequested: false, accessibility: false,
      preferredWidths: [80], legendInset: 28, minimumHeight: 266, measureHeight: { _, _ in 80 }))
    XCTAssertLessThanOrEqual(try XCTUnwrap(layout.labelFrames.first).maxY, layout.height - 36)
  }
  func testSearchSurfaceIsolationAndMalformedArchiveRejection() throws {
    let (atlas, _, aorta) = try fixture()
    var selection = GalaxySSIHealthAtlasState.Selection()
    XCTAssertTrue(GalaxySSIHealthAtlasSearchSurface.detail.contains(selection))
    XCTAssertFalse(GalaxySSIHealthAtlasSearchSurface.research.contains(selection))
    selection.tab = .simulation
    XCTAssertTrue(GalaxySSIHealthAtlasSearchSurface.standalone.contains(selection))
    XCTAssertFalse(GalaxySSIHealthAtlasSearchSurface.detail.contains(selection))
    selection.researchPresented = true
    XCTAssertTrue(GalaxySSIHealthAtlasSearchSurface.research.contains(selection))
    XCTAssertFalse(GalaxySSIHealthAtlasSearchSurface.standalone.contains(selection))
    let state = GalaxySSIHealthAtlasState()
    var archive = GalaxySSIHealthAtlasLessonNavigation()
    archive.path = [.init(entryID: aorta.id, depth: 1)]
    archive.search = .init(origin: .init(entryID: "unknown", depth: 1), selection: .init(), scroll: 0)
    state.restoreLessonNavigation(String(decoding: try JSONEncoder().encode(archive), as: UTF8.self), atlas: atlas)
    XCTAssertTrue(state.lessonNavigation.path.isEmpty)
    state.recordDetail(aorta, depth: 32)
    state.beginCatalogueSearch(aorta, depth: 32, scroll: 0)
    XCTAssertNil(state.lessonNavigation.search)
  }
}
