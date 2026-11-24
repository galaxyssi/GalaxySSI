import SwiftUI

struct GalaxySSIHealthAtlasLessonNavigation: Codable, Equatable {
  struct Location: Codable, Equatable {
    let entryID: String
    let depth: Int
    var key: String { "\(depth)|" + entryID }
  }
  struct Return: Codable, Equatable {
    let origin: Location
    var selection: GalaxySSIHealthAtlasState.Selection
    let scroll: Double
    let targetID: String
    let targetStory: String
    var structureOnly: Bool?
  }
  struct Search: Codable, Equatable, Identifiable {
    let origin: Location
    var selection: GalaxySSIHealthAtlasState.Selection
    let scroll: Double
    var id: String { origin.key }
  }
  var schema = 1
  var path: [Location] = []
  var returns: [String: Return] = [:]
  var activeSelection: GalaxySSIHealthAtlasState.Selection?
  var search: Search?
}

struct GalaxySSIHealthAtlasRelatedAction: Identifiable {
  let id: String
  let label: String
  let open: () -> Void
}

@MainActor
extension GalaxySSIHealthAtlasState {
  typealias LessonLocation = GalaxySSIHealthAtlasLessonNavigation.Location
  func detailBinding(_ entry: GalaxySSIHealthAtlas.Entry, depth: Int) -> Binding<Selection> {
    let location = LessonLocation(entryID: entry.id, depth: depth)
    return Binding(get: {
      let search = self.lessonNavigation.search
      return Self.migrated(self.lessonNavigation.returns[location.key]?.selection ??
        (search?.origin == location ? search?.selection : nil) ?? self.binding(entry).wrappedValue, entry: entry)
    }, set: { value in
      // A disappearing child must not overwrite a same-entry origin after Back.
      guard self.lessonNavigation.path.contains(location) else { return }
      if self.lessonNavigation.returns[location.key] != nil {
        self.lessonNavigation.returns[location.key]?.selection = Self.migrated(value, entry: entry)
      } else if self.lessonNavigation.search?.origin == location {
        self.lessonNavigation.search?.selection = Self.migrated(value, entry: entry)
      } else { self.binding(entry).wrappedValue = value }
    })
  }
  func recordDetail(_ entry: GalaxySSIHealthAtlas.Entry, depth: Int) {
    guard (1...32).contains(depth) else { return }
    let location = LessonLocation(entryID: entry.id, depth: depth)
    guard lessonNavigation.returns[location.key] == nil, restoredDetailChildren[location.key] == nil else { return }
    lessonNavigation.path = lessonNavigation.path.filter { $0.depth < depth } + [location]
    lessonNavigation.returns = lessonNavigation.returns.filter { $0.value.origin.depth < depth }
  }
  @discardableResult
  func selectDetailTab(_ entry: GalaxySSIHealthAtlas.Entry, depth: Int, tab: Tab) -> Bool {
    let selection = detailBinding(entry, depth: depth)
    guard selection.wrappedValue.tab != tab else { return false }
    playback.pause(); selection.wrappedValue.tab = tab
    return true
  }
  @discardableResult
  func openRelatedLesson(origin: GalaxySSIHealthAtlas.Entry, depth: Int, related: GalaxySSIHealthAtlasFunctionCatalogue.Related,
                         scroll: Double, atlas: GalaxySSIHealthAtlas, catalogue: GalaxySSIHealthAtlasFunctionCatalogue) -> Bool {
    guard (1..<32).contains(depth), let target = atlas.entry(related.entryID),
      catalogue.routes[target.id]?.contains(related.storyID) == true else { return false }
    playback.pause()
    let location = LessonLocation(entryID: origin.id, depth: depth), snapshot = functionSnapshot(origin, depth: depth)
    let prefix = lessonNavigation.path.filter { $0.depth < depth }
    lessonNavigation.returns = lessonNavigation.returns.filter { $0.value.origin.depth < depth }
    restoredDetailChildren = restoredDetailChildren.filter { key, _ in prefix.contains { $0.key == key } }
    lessonNavigation.returns[location.key] = .init(origin: location, selection: snapshot, scroll: Self.safeScroll(scroll),
      targetID: target.id, targetStory: related.storyID)
    var next = binding(target).wrappedValue
    var function = next.functionSelection ?? .init()
    function.choose(related.storyID, entryID: target.id, catalogue: catalogue)
    next.functionSelection = function; next.tab = .function; next.researchPresented = false
    binding(target).wrappedValue = next
    lessonNavigation.path = prefix + [location, .init(entryID: target.id, depth: depth + 1)]
    return true
  }
  func closeRelatedLesson(_ location: LessonLocation) {
    guard let saved = lessonNavigation.returns[location.key] else { return }
    playback.pause()
    // Restore the origin course/phase without discarding another course's new
    // progress or globally entry-scoped numerical inputs from the destination.
    var next = entries[location.entryID] ?? saved.selection
    next.tab = saved.selection.tab; next.research = saved.selection.research
    next.researchPresented = saved.selection.researchPresented
    next.researchReturnScroll = saved.selection.researchReturnScroll
    next.artworkView = saved.selection.artworkView; next.layers = saved.selection.layers; next.zoom = saved.selection.zoom
    var function = next.functionSelection ?? saved.selection.functionSelection ?? .init()
    function.selected = saved.selection.functionSelection?.selected
    if let catalogue = try? GalaxySSIHealthAtlasFunctionCatalogue.bundled.get(),
      let originStory = saved.selection.functionSelection?.current(entryID: location.entryID, catalogue: catalogue)?.id {
      function.phases[originStory] = saved.selection.functionSelection?.phase(entryID: location.entryID, storyID: originStory, catalogue: catalogue)
    }
    next.functionSelection = function
    entries[location.entryID] = next
    lessonReturnScroll[location.key] = saved.scroll
    truncateLessonNavigation(after: location)
  }
  func closeRestoredDetail(_ location: LessonLocation) {
    playback.pause(); truncateLessonNavigation(after: location)
  }
  private func truncateLessonNavigation(after location: LessonLocation) {
    lessonNavigation.path = lessonNavigation.path.filter { $0.depth <= location.depth }
    lessonNavigation.returns = lessonNavigation.returns.filter { $0.value.origin.depth < location.depth }
    restoredDetailChildren = restoredDetailChildren.filter { key, _ in lessonNavigation.path.contains { $0.key == key && $0.depth < location.depth } }
  }
  func clearLessonNavigation() {
    lessonNavigation = .init(); restoredDetailChildren = [:]; lessonReturnScroll = [:]
  }
  var lessonNavigationSerialized: String {
    var saved = lessonNavigation
    saved.activeSelection = saved.path.last.flatMap { entries[$0.entryID] }
    return (try? JSONEncoder().encode(saved)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
  }
  func beginCatalogueSearch(_ entry: GalaxySSIHealthAtlas.Entry, depth: Int, scroll: Double) {
    let location = LessonLocation(entryID: entry.id, depth: depth)
    guard (1..<32).contains(depth), lessonNavigation.path.last == location else { return }
    playback.pause()
    let snapshot = functionSnapshot(entry, depth: depth)
    lessonNavigation.search = .init(origin: location, selection: snapshot, scroll: Self.safeScroll(scroll))
  }
  func cancelCatalogueSearch() {
    guard let saved = lessonNavigation.search else { return }
    entries[saved.origin.entryID] = saved.selection
    lessonReturnScroll[saved.origin.key] = saved.scroll
    lessonNavigation.search = nil
  }
  @discardableResult
  func openCatalogueResult(_ targetID: String, from saved: GalaxySSIHealthAtlasLessonNavigation.Search,
                           atlas: GalaxySSIHealthAtlas) -> Bool {
    guard lessonNavigation.path.last == saved.origin, saved.origin.depth < 32,
      let target = atlas.entry(targetID) else { return false }
    playback.pause()
    lessonNavigation.returns[saved.origin.key] = .init(origin: saved.origin, selection: saved.selection,
      scroll: saved.scroll, targetID: target.id, targetStory: "", structureOnly: true)
    var next = binding(target).wrappedValue
    next.tab = .structure; next.researchPresented = false
    binding(target).wrappedValue = next
    lessonNavigation.path.append(.init(entryID: target.id, depth: saved.origin.depth + 1))
    return true
  }
  func restoreLessonNavigation(_ text: String, atlas: GalaxySSIHealthAtlas) {
    clearLessonNavigation()
    guard text.utf8.count <= 128_000, let data = text.data(using: .utf8),
      var saved = try? JSONDecoder().decode(GalaxySSIHealthAtlasLessonNavigation.self, from: data), saved.schema == 1,
      saved.path.count <= 32, saved.returns.count < 32,
      saved.path.allSatisfy({ (1...32).contains($0.depth) && atlas.entry($0.entryID) != nil }),
      zip(saved.path, saved.path.dropFirst()).allSatisfy({ $0.1.depth == $0.0.depth + 1 }),
      let catalogue = try? GalaxySSIHealthAtlasFunctionCatalogue.bundled.get() else { return }
    func cleaned(_ selection: Selection, entryID: String) -> Selection? {
      let cleaner = GalaxySSIHealthAtlasState()
      guard let encoded = try? JSONEncoder().encode([entryID: selection]),
        let encodedText = String(data: encoded, encoding: .utf8) else { return nil }
      cleaner.restore(encodedText, atlas: atlas)
      return cleaner.entries[entryID]
    }
    for (key, frame) in saved.returns {
      guard key == frame.origin.key, let index = saved.path.firstIndex(of: frame.origin), index + 1 < saved.path.count,
        saved.path[index + 1].entryID == frame.targetID,
        (frame.structureOnly == true ? frame.targetStory.isEmpty : catalogue.routes[frame.targetID]?.contains(frame.targetStory) == true) else { return }
      // Reuse the established entry, model, course and cache sanitizers.
      guard let selection = cleaned(frame.selection, entryID: frame.origin.entryID) else { return }
      saved.returns[key] = .init(origin: frame.origin, selection: selection, scroll: Self.safeScroll(frame.scroll),
        targetID: frame.targetID, targetStory: frame.targetStory, structureOnly: frame.structureOnly)
    }
    if let search = saved.search {
      guard saved.path.last == search.origin, search.origin.depth < 32,
        let selection = cleaned(search.selection, entryID: search.origin.entryID) else { return }
      saved.search = .init(origin: search.origin, selection: selection, scroll: Self.safeScroll(search.scroll))
    }
    if let active = saved.activeSelection, let last = saved.path.last {
      guard let selection = cleaned(active, entryID: last.entryID) else { return }
      entries[last.entryID] = selection
      saved.activeSelection = selection
    }
    lessonNavigation = saved
    for (parent, child) in zip(saved.path, saved.path.dropFirst()) where saved.returns[parent.key] == nil {
      restoredDetailChildren[parent.key] = child
    }
  }
}
