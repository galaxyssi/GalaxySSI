import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAtlasDiscussionTests: XCTestCase {
  typealias Discussion = GalaxySSIHealthAtlasDiscussion

  func testObjectTopicsAreExactNotTitlesOrLegacyBroadTopics() {
    XCTAssertEqual(Discussion.topic("heart"), "body-atlas:heart")
    XCTAssertEqual(Discussion.topic("whole"), "body-atlas:whole")
    for id in ["", " heart", "heart/other", "heart:other", "heart\n", "heart\r\n", String(repeating: "x", count: 61)] {
      XCTAssertNil(Discussion.topic(id))
    }
    var session = AgentConversation(id: "fixture", title: "Heart", createdAt: 1, updatedAt: 1,
      createdByAgent: true, globalTopicKey: "body-atlas")
    XCTAssertFalse(Discussion.reusable(session, topic: "body-atlas:heart"))
    session.globalTopicKey = "body-atlas:"
    XCTAssertFalse(Discussion.reusable(session, topic: "body-atlas:"))
  }

  func testSameObjectReusesAfterRenameWhileSameTitleDifferentObjectDoesNot() throws {
    let store = try makeStore()
    let heart = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Same title"))
    XCTAssertTrue(store.renameAgentSession(id: heart.id, title: "Renamed lesson"))
    XCTAssertEqual(Discussion.conversation(store: store, itemID: "heart", title: "Another title")?.id, heart.id)
    let brain = try XCTUnwrap(Discussion.conversation(store: store, itemID: "brain", title: "Same title"))
    XCTAssertNotEqual(brain.id, heart.id)
    XCTAssertTrue(brain.createdByAgent)
    XCTAssertEqual(brain.globalTopicKey, "body-atlas:brain")
  }

  func testIneligibleIndexedSessionsAreReplacedWithoutChangingTheirFlags() throws {
    let store = try makeStore()
    let edits: [(inout AgentConversation) -> Void] = [
      { $0.privateMode = true }, { $0.status = .archived }, { $0.trackingPaused = true },
      { $0.createdByAgent = false }, { $0.mergedIntoConversationId = "other" }, { $0.globalTopicKey = "foreign" }
    ]
    for edit in edits {
      var original = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
      edit(&original)
      XCTAssertTrue(store.agentConversationDatabase.upsert(original))
      let next = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
      XCTAssertNotEqual(next.id, original.id)
      XCTAssertEqual(store.agentConversationDatabase.read(original.id), original)
    }
  }

  func testDeletedIndexedConversationIsNotResurrected() throws {
    let store = try makeStore()
    let first = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
    _ = store.agentConversationDatabase.delete(first.id)
    let next = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
    XCTAssertNotEqual(next.id, first.id)
    XCTAssertNil(store.agentConversationDatabase.read(first.id))
  }

  func testIndexIsEncryptedPersistsAndRejectsCorruptionWithoutCreatingSessions() throws {
    let store = try makeStore()
    let first = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
    XCTAssertNil(store.defaults.object(forKey: Discussion.storageKey))
    let raw = try XCTUnwrap(store.defaults.data(forKey: Discussion.storageKey + ".encrypted.v1"))
    XCTAssertNil(raw.range(of: Data(first.id.utf8)))
    let restored = GalaxySSIStore(defaults: store.defaults, secrets: store.secrets)
    XCTAssertEqual(Discussion.conversation(store: restored, itemID: "heart", title: "Lesson")?.id, first.id)
    let count = store.agentConversationDatabase.count()
    store.defaults.set(Data([1, 2, 3]), forKey: Discussion.storageKey + ".encrypted.v1")
    XCTAssertNil(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
    XCTAssertEqual(store.agentConversationDatabase.count(), count)
  }

  func testForeignOwnerIndexNeverReusesItsConversation() throws {
    let store = try makeStore()
    let first = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
    let data = try JSONSerialization.data(withJSONObject: ["owner": "foreign-owner", "topics": ["body-atlas:heart": first.id]])
    XCTAssertTrue(GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: store.defaults,
      key: Discussion.storageKey, secrets: store.secrets))
    let next = try XCTUnwrap(Discussion.conversation(store: store, itemID: "heart", title: "Lesson"))
    XCTAssertNotEqual(next.id, first.id)
  }

  func testOptionalQuestionIsBoundedAndAppendedAfterFrozenContext() throws {
    XCTAssertEqual(Discussion.request(context: "Frozen chapter", question: " \n ", language: "en"), "Frozen chapter")
    let request = try XCTUnwrap(Discussion.request(context: "Frozen chapter", question: " Why this step? ", language: "en"))
    XCTAssertTrue(request.hasPrefix("Frozen chapter\n\n"))
    XCTAssertTrue(request.hasSuffix("Why this step?"))
    XCTAssertNil(Discussion.request(context: "", question: "Question", language: "en"))
    XCTAssertNil(Discussion.request(context: String(repeating: "x", count: 9_001), question: "", language: "en"))
    XCTAssertNil(Discussion.request(context: "Context", question: String(repeating: "x", count: 501), language: "en"))
    XCTAssertEqual(Discussion.limitQuestion(String(repeating: "x", count: 499) + "\u{1F680}"), String(repeating: "x", count: 499))
  }

  func testCurrentStructureStepUsesVisiblePlateAndNeverEntersValuesOrResearch() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let heart = try XCTUnwrap(atlas.entry("heart"))
    let plate = try XCTUnwrap(atlas.plate(for: heart.id, viewKey: nil))
    let landmark = try XCTUnwrap(GalaxySSIHealthAtlasLandmarks.list(plate, atlas: atlas).first)
    var selection = GalaxySSIHealthAtlasState.Selection()
    for language in ["en", "zh-Hans"] {
      let current = Discussion.structureContext(atlas: atlas, entry: heart, selection: selection, position: 1, language: language)
      XCTAssertTrue(current.contains(GalaxySSIHealthAtlasText.get(landmark.title, language)))
      let question = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection,
        research: false, language: language, structurePosition: 1)
      XCTAssertTrue(question.hasSuffix(current))
    }
    selection.tab = .values
    XCTAssertEqual(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection,
      research: false, language: "en", structurePosition: 1), "")
    selection.tab = .function
    let function = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart, selection: selection,
      research: false, language: "en", structurePosition: 1)
    XCTAssertEqual(function, GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: heart,
      selection: selection, research: false, language: "en"))
  }

  func testQuestionSnapshotKeepsLiveFunctionChapterWithoutChangingNavigation() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let entry = try XCTUnwrap(atlas.entry("pancreas"))
    let catalogue = try XCTUnwrap(GalaxySSIHealthAtlasFunctionCatalogue.read(bundle: Bundle(for: GalaxySSIStore.self)))
    let state = GalaxySSIHealthAtlasState()
    state.binding(entry).wrappedValue.tab = .function
    state.binding(entry).wrappedValue.functionSelection = .init()
    state.binding(entry).wrappedValue.functionSelection?.choose("INSULIN_SECRETION", entryID: entry.id, catalogue: catalogue)
    state.recordFunctionPhase(entryID: entry.id, storyID: "INSULIN_SECRETION", phase: 0.7)
    let snapshot = state.questionSnapshot(entry)
    XCTAssertEqual(snapshot.functionSelection?.phase(entryID: entry.id, storyID: "INSULIN_SECRETION", catalogue: catalogue), 0.7)
    let context = try XCTUnwrap(GalaxySSIHealthAtlasFunctionContext(entryID: entry.id, selection: snapshot.functionSelection, catalogue: catalogue))
    XCTAssertTrue(GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: snapshot,
      research: false, language: "en").contains(context.lines(for: entry.id, language: "en")[2]))
    XCTAssertTrue(state.lessonNavigation.path.isEmpty)
  }

  func testWholeBodyQuestionDoesNotUseTheHighlightedOrganAsItsOwner() throws {
    let atlas = try GalaxySSIHealthAtlas.load(bundle: Bundle(for: GalaxySSIStore.self))
    let state = GalaxySSIHealthAtlasState()
    state.wholeFocus = "heart"
    let request = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: nil, selection: .init(), research: false, language: "en")
    XCTAssertEqual(request, GalaxySSIHealthAtlasText.get("health_atlas_ask_whole_context", "en"))
    XCTAssertNotEqual(Discussion.topic("whole"), Discussion.topic(state.wholeFocus))
  }

  private func makeStore() throws -> GalaxySSIStore {
    let suite = "atlas-discussion-fixture-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    return GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
  }
}
