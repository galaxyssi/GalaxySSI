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
  func testFigureNoteLayoutAndLegacyBottomInsetDefaults() throws {
    let layout = try XCTUnwrap(GalaxySSIHealthAtlasCalloutLayout.make(width: 320, aspectRatio: 1,
      anchors: [CGPoint(x: 0.8, y: 1)], splitRequested: false, accessibility: false,
      preferredWidths: [80], legendInset: 28, minimumHeight: 266, measureHeight: { _, _ in 80 }))
    XCTAssertLessThanOrEqual(try XCTUnwrap(layout.labelFrames.first).maxY, layout.height - 36)
  }
  func testAtlasUniformSideColumnsAndMappedLeaderEndpoints() throws {
    typealias Layout = GalaxySSIHealthAtlasFigureLayout
    for width in [CGFloat(280), 319, 320, 380, 720, 1000] {
      let columns = Layout.columns(width: width)
      XCTAssertEqual(columns.noteWidth, min(width * 0.4, 328))
      XCTAssertEqual(columns.edge, width < 320 ? 8 : 12)
      XCTAssertEqual(columns.gutter, width < 320 ? 8 : 16)
      XCTAssertEqual(columns.artWidth + columns.noteWidth + columns.edge * 2 + columns.gutter, width, accuracy: 0.001)
    }
    let subject = try XCTUnwrap(Layout.subject(in: CGRect(x: 20, y: 30, width: 100, height: 200),
      aspectRatio: 2, focus: CGPoint(x: 0.8, y: 0.2)))
    XCTAssertEqual(subject.x, 100, accuracy: 0.001)
    XCTAssertEqual(subject.y, 115, accuracy: 0.001)
    let points = Layout.leader(note: CGRect(x: 12, y: 12, width: 100, height: 80),
      art: CGRect(x: 128, y: 12, width: 200, height: 300), gutter: 16, function: false, target: CGPoint(x: -10, y: 999))
    XCTAssertEqual(points.last, CGPoint(x: 128, y: 312))
    XCTAssertEqual(points.first, CGPoint(x: 112, y: 52))
    let center = Layout.leader(note: CGRect(x: 0, y: 0, width: 80, height: 80),
      art: CGRect(x: 96, y: 0, width: 200, height: 200), gutter: 16, function: true, target: nil)
    XCTAssertEqual(center.last, CGPoint(x: 196, y: 84))
  }
  func testEveryLandmarkViewRestoresItsStepAndOverviewRemovesTheCacheEntry() throws {
    let (atlas, _, _) = try fixture()
    var checked = 0
    for owner in [""] + atlas.entries.map(\.id) {
      for plate in atlas.views(for: owner.isEmpty ? nil : owner) where plate.hasLabels {
        let landmarks = GalaxySSIHealthAtlasLandmarks.list(plate, atlas: atlas)
        XCTAssertFalse(landmarks.isEmpty)
        XCTAssertEqual(Set(landmarks.map(\.id)), Set(plate.markers.map(\.id) + plate.annotations.map(\.id)))
        XCTAssertTrue(zip(landmarks, landmarks.dropFirst()).allSatisfy { pair in pair.0.point.y <= pair.1.point.y })
        var steps = GalaxySSIHealthAtlasStructureSteps()
        steps.select(1, owner: owner, view: plate.viewKey ?? "", count: landmarks.count)
        let restored = GalaxySSIHealthAtlasStructureSteps.restore(steps.serialized, atlas: atlas)
        XCTAssertEqual(restored.position(owner: owner, view: plate.viewKey ?? "", count: landmarks.count), 1)
        steps.select(999, owner: owner, view: plate.viewKey ?? "", count: landmarks.count)
        XCTAssertEqual(steps.position(owner: owner, view: plate.viewKey ?? "", count: landmarks.count), landmarks.count)
        steps.select(0, owner: owner, view: plate.viewKey ?? "", count: landmarks.count)
        XCTAssertTrue(steps.steps.isEmpty)
        checked += 1
      }
    }
    XCTAssertGreaterThan(checked, 1)
  }
  func testStepsHaveIndependentViewsAndBoundedValidatedStorage() throws {
    let (atlas, _, _) = try fixture()
    var steps = GalaxySSIHealthAtlasStructureSteps()
    let exterior = try XCTUnwrap(atlas.views(for: "heart").first { $0.viewKey == "heart-exterior" })
    let section = try XCTUnwrap(atlas.views(for: "heart").first { $0.viewKey == "heart-section" })
    let exteriorCount = GalaxySSIHealthAtlasLandmarks.list(exterior, atlas: atlas).count
    let sectionCount = GalaxySSIHealthAtlasLandmarks.list(section, atlas: atlas).count
    steps.select(1, owner: "heart", view: "heart-exterior", count: exteriorCount)
    steps.select(2, owner: "heart", view: "heart-section", count: sectionCount)
    let restored = GalaxySSIHealthAtlasStructureSteps.restore(steps.serialized, atlas: atlas)
    XCTAssertEqual(restored.position(owner: "heart", view: "heart-exterior", count: exteriorCount), 1)
    XCTAssertEqual(restored.position(owner: "heart", view: "heart-section", count: sectionCount), min(2, sectionCount))
    steps = .init()
    steps.select(1, owner: "heart", view: "front", count: 3)
    steps.select(2, owner: "heart", view: "back", count: 3)
    XCTAssertEqual(steps.position(owner: "heart", view: "front", count: 3), 1)
    XCTAssertEqual(steps.position(owner: "heart", view: "back", count: 3), 2)
    XCTAssertTrue(GalaxySSIHealthAtlasStructureSteps.restore(steps.serialized, atlas: atlas).steps.isEmpty)
    for index in 0...400 { steps.select(1, owner: "unknown-\(index)", view: "", count: 1) }
    XCTAssertEqual(steps.steps.count, 400)
    XCTAssertEqual(steps.steps.first?.owner, "unknown-1")
    XCTAssertTrue(GalaxySSIHealthAtlasStructureSteps.restore(steps.serialized, atlas: atlas).steps.isEmpty)
    XCTAssertTrue(GalaxySSIHealthAtlasStructureSteps.restore(String(repeating: "x", count: 128_001), atlas: atlas).steps.isEmpty)
  }
  func testNumberedRailsStayCompactAndEnlargedFrameDoesNotAdvanceTheClock() throws {
    let numbered = try XCTUnwrap(GalaxySSIHealthAtlasCalloutLayout.make(width: 140, aspectRatio: 1,
      anchors: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.7)], splitRequested: true, accessibility: true,
      preferredWidths: [100, 100], numbered: true, measureHeight: { _, _ in 48 }))
    XCTAssertFalse(numbered.split)
    XCTAssertEqual(numbered.rightWidth, 48)
    var clock = GalaxySSIHealthAtlasChapterClock(chapters: 5, phase: 0.43)
    clock.resume(1000); clock.pause(2000)
    let before = clock.sample(2000)
    let snapshot = GalaxySSIHealthAtlasEnlargedFrame(id: "HEARTBEAT", phase: before)
    XCTAssertEqual(clock.sample(50_000), before)
    XCTAssertEqual(snapshot.phase, before)
    XCTAssertFalse(clock.playing)
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
